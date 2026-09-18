#!/bin/bash

# --- Configuration ---
WORKDIR="amq-config-artifacts"
INSTANCE_NAME="ex-aao"
LDAP_PASSWORD="admin"
TRUSTSTORE_PASSWORD="changeit"

# Create the directory if it doesn't exist
mkdir -p "$WORKDIR"

# --- 1. Create Certificates ---
echo "Generating certificates in $WORKDIR..."
openssl req -x509 -new -nodes -keyout "$WORKDIR/ca.key" -sha256 -days 365 -out "$WORKDIR/ca.crt" -subj "/CN=My-Lab-CA"
openssl genrsa -out "$WORKDIR/ldap.key" 2048
openssl req -new -key "$WORKDIR/ldap.key" -out "$WORKDIR/ldap.csr" -subj "/CN=openldap"
openssl x509 -req -in "$WORKDIR/ldap.csr" -CA "$WORKDIR/ca.crt" -CAkey "$WORKDIR/ca.key" -CAcreateserial -out "$WORKDIR/ldap.crt" -days 365 -sha256

# --- 2. Create Truststore ---
echo "Creating Java truststore..."
keytool -importcert -file "$WORKDIR/ca.crt" -keystore "$WORKDIR/truststore.jks" -alias ldap-ca -storepass "$TRUSTSTORE_PASSWORD" -noprompt

# --- 3. Create Configuration Files ---
echo "Generating configuration files..."

cat <<EOF > "$WORKDIR/login.config"
activemq {
   org.apache.activemq.artemis.spi.core.security.jaas.LDAPLoginModule sufficient
       debug=true
       initialContextFactory="com.sun.jndi.ldap.LdapCtxFactory"
       connectionURL="ldaps://openldap:636"
       connectionUsername="cn=admin,dc=example,dc=org"
       connectionPassword="$LDAP_PASSWORD"
       connectionProtocol="ssl"
       authentication="simple"
       userBase="dc=example,dc=org"
       userSearchMatching="(uid={0})"
       userSearchSubtree=true
       roleBase="dc=example,dc=org"
       roleName="cn"
       roleSearchMatching="(uniqueMember={0})"
       roleSearchSubtree=false;
};
EOF

cat <<EOF > "$WORKDIR/log4j2.properties"
status = INFO
name = PropertiesConfig

appender.stdout.type = Console
appender.stdout.name = stdout
appender.stdout.layout.type = PatternLayout
appender.stdout.layout.pattern = %d [%t] %-5p %c - %m%n

logger.jaas.name = org.apache.activemq.artemis.spi.core.security.jaas
logger.jaas.level = DEBUG
logger.ldap.name = javax.naming.ldap
logger.ldap.level = DEBUG

rootLogger.level = INFO
rootLogger.appenderRefs = stdout
rootLogger.appenderRef.stdout.ref = stdout
EOF

# --- 4. Create OCP Secrets and ConfigMaps ---
echo "Uploading configurations to OpenShift..."
# We specify the key name explicitly (e.g., ca.crt=path/to/file) to avoid path issues in keys
oc create secret generic ldap-certs \
  --from-file=ca.crt="$WORKDIR/ca.crt" \
  --from-file=ldap.crt="$WORKDIR/ldap.crt" \
  --from-file=ldap.key="$WORKDIR/ldap.key" \
  --dry-run=client -o yaml | oc apply -f -

oc create secret generic amq-jaas-config --from-file=login.config="$WORKDIR/login.config" --dry-run=client -o yaml | oc apply -f -
oc create secret generic amq-truststore --from-file=truststore.jks="$WORKDIR/truststore.jks" --dry-run=client -o yaml | oc apply -f -
oc create configmap broker-log-config --from-file=log4j2.properties="$WORKDIR/log4j2.properties" --dry-run=client -o yaml | oc apply -f -

# --- 5. Deploy OpenLDAP Server ---
echo "Deploying OpenLDAP..."
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openldap
spec:
  replicas: 1
  selector:
    matchLabels:
      app: openldap
  template:
    metadata:
      labels:
        app: openldap
    spec:
      initContainers:
      - name: copy-certs
        image: busybox
        command: ['sh', '-c', 'cp /mnt/certs/* /container/service/slapd/assets/certs/ && chmod 664 /container/service/slapd/assets/certs/*.key && chmod 644 /container/service/slapd/assets/certs/*.crt']
        volumeMounts:
        - name: ldap-certs-secret
          mountPath: /mnt/certs
        - name: writable-certs
          mountPath: /container/service/slapd/assets/certs
      containers:
      - name: openldap
        image: docker.io/osixia/openldap:latest
        env:
        - name: LDAP_TLS
          value: "true"
        - name: LDAP_TLS_CRT_FILENAME
          value: "ldap.crt"
        - name: LDAP_TLS_KEY_FILENAME
          value: "ldap.key"
        - name: LDAP_TLS_CA_CRT_FILENAME
          value: "ca.crt"
        - name: LDAP_ADMIN_PASSWORD
          value: "$LDAP_PASSWORD"
        - name: LDAP_DOMAIN
          value: "example.org"
        - name: LDAP_TLS_VERIFY_CLIENT
          value: "never"
        ports:
        - containerPort: 636
          name: ldaps
        volumeMounts:
        - name: writable-certs
          mountPath: /container/service/slapd/assets/certs
      volumes:
      - name: ldap-certs-secret
        secret:
          secretName: ldap-certs
      - name: writable-certs
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: openldap
spec:
  ports:
  - name: ldaps
    port: 636
    targetPort: 636
  selector:
    app: openldap
EOF

echo "Waiting for OpenLDAP rollout..."
oc rollout status deployment/openldap

# --- 6. Populate LDAP Data ---
echo "Populating LDAP..."
cat <<EOF > "$WORKDIR/data.ldif"
dn: ou=users,dc=example,dc=org
objectClass: organizationalUnit
ou: users

dn: uid=testadmin,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: Test Admin
sn: Admin
uid: testadmin
userPassword: $LDAP_PASSWORD

dn: cn=tst.OpenShift.Admins,dc=example,dc=org
objectClass: groupOfUniqueNames
cn: tst.OpenShift.Admins
uniqueMember: uid=testadmin,ou=users,dc=example,dc=org

dn: uid=riemann,dc=example,dc=org
objectClass: inetOrgPerson
cn: Bernhard Riemann
sn: Riemann
uid: riemann
userPassword: password

dn: cn=admingroup,dc=example,dc=org
objectClass: groupOfUniqueNames
cn: admingroup
uniqueMember: uid=riemann,dc=example,dc=org
EOF

cat "$WORKDIR/data.ldif" | oc exec -i deployment/openldap -- ldapadd -x -D "cn=admin,dc=example,dc=org" -w "$LDAP_PASSWORD"

# --- 7. Deploy AMQ Broker Instance ---
echo "Applying ActiveMQArtemis CR..."
cat <<EOF | oc apply -f -
apiVersion: broker.amq.io/v1beta1
kind: ActiveMQArtemis
metadata:
  name: $INSTANCE_NAME
spec:
  deploymentPlan:
    size: 1
    managementRBACEnabled: true
    extraMounts:
      configMaps:
        - broker-log-config
      secrets:
        - amq-jaas-config
        - amq-truststore
  brokerProperties:
    - 'securityRoles."mops.address.activemq.management.*"."tst.OpenShift.Admins".view=true'
    - 'securityRoles."mops.address.activemq.management.*"."tst.OpenShift.Admins".edit=true'
    - 'securityRoles.#."tst.OpenShift.Admins".send=true'
    - 'securityRoles.#."tst.OpenShift.Admins".consume=true'
    - 'securityRoles.#."admingroup".send=true'
    - 'securityRoles.#."admingroup".consume=true'
  env:
    - name: JAVA_ARGS_APPEND
      value: >-
        -Djava.security.auth.login.config=/etc/amq-secret-volume/amq-jaas-config/login.config
        -Djavax.net.ssl.trustStore=/etc/amq-secret-volume/amq-truststore/truststore.jks
        -Djavax.net.ssl.trustStorePassword=$TRUSTSTORE_PASSWORD
        -Dlog4j2.configurationFile=/etc/amq-configmap-volume/broker-log-config/log4j2.properties
        -Djavax.net.debug=ssl,handshake
        -Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true
        -Dhawtio.role=tst.OpenShift.Admins,admingroup
EOF

echo "-------------------------------------------------------"
echo "Setup Complete. Local artifacts are in: $WORKDIR"
echo "Check logs: oc logs -f statefulset/$INSTANCE_NAME-ss"
echo "-------------------------------------------------------"
