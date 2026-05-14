#!/bin/bash

# --- Configuration ---
BROKER_NAME="ex-aao"
LDAP_NAME="openldap"
JAAS_SECRET="custom-jaas-config"
ADMIN_PASSWORD="admin" # osixia/openldap default

echo "Starting AMQ Broker + LDAP Integration..."

# --- 1. Deploy OpenLDAP ---
echo "Deploying OpenLDAP..."
oc new-app --name ${LDAP_NAME} ALLOW_EMPTY_PASSWORD=yes --image docker.io/osixia/openldap:latest

echo "Configuring Service Account and SCC..."
oc create sa ${LDAP_NAME}-sa --dry-run=client -o yaml | oc apply -f -
oc adm policy add-scc-to-user anyuid -z ${LDAP_NAME}-sa
oc set serviceaccount deployment/${LDAP_NAME} ${LDAP_NAME}-sa

# Wait for LDAP to be ready
echo "Waiting for LDAP pod to be ready..."
oc rollout status deployment/${LDAP_NAME}

# --- 2. Create JAAS Config File ---
echo "Generating login.config..."
cat <<EOF > login.config
activemq {
   org.apache.activemq.artemis.spi.core.security.jaas.LDAPLoginModule sufficient
       debug=true
       initialContextFactory="com.sun.jndi.ldap.LdapCtxFactory"
       connectionURL="ldap://${LDAP_NAME}:389"
       connectionUsername="cn=admin,dc=example,dc=org"
       connectionPassword="${ADMIN_PASSWORD}"
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

# --- 3. Create OpenShift Secret ---
echo "Creating/Updating Secret: ${JAAS_SECRET}..."
oc create secret generic ${JAAS_SECRET} --from-file=login.config --dry-run=client -o yaml | oc apply -f -

# --- 4. Patch AMQ Broker CR ---
echo "Patching AMQ Broker CR: ${BROKER_NAME}..."
oc patch activemqartemis ${BROKER_NAME} --type=merge -p "
{
  \"spec\": {
    \"deploymentPlan\": {
      \"extraMounts\": {
        \"secrets\": [\"${JAAS_SECRET}\"]
      },
      \"requireLogin\": true
    },
    \"env\": [
      {
        \"name\": \"JAVA_ARGS_APPEND\",
        \"value\": \"-Djava.security.auth.login.config=/etc/amq-secret-volume/${JAAS_SECRET}/login.config\"
      }
    ]
  }
}"

# --- 5. Verify ---
echo "Waiting for Broker rollout..."
oc rollout status statefulset/${BROKER_NAME}-ss

echo "Running LDAP Search Verification..."
oc exec -it deployment/${LDAP_NAME} -- ldapsearch -x -H ldap://localhost:389 -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w ${ADMIN_PASSWORD}

echo "Done. Check broker logs with: oc logs -f ${BROKER_NAME}-ss-0 | grep -i ldap"
