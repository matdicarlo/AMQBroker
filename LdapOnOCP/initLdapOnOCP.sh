#!/bin/bash

# --- Configuration ---
NAMESPACE="brokerldap"
BROKER_NAME="ex-aao"
LDAP_NAME="openldap"
JAAS_SECRET="custom-jaas-config"
ADMIN_PASSWORD="admin" # osixia/openldap default

echo "Starting AMQ Broker + LDAP Integration in namespace: ${NAMESPACE}..."

# Ensure we are in the right namespace
oc project ${NAMESPACE} || oc new-project ${NAMESPACE}

# --- 1. Deploy OpenLDAP ---
echo "Deploying OpenLDAP..."
# We use a template-like approach for LDAP to ensure SA is set from the start
cat <<EOF | oc apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${LDAP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${LDAP_NAME}
  template:
    metadata:
      labels:
        app: ${LDAP_NAME}
    spec:
      serviceAccountName: ${LDAP_NAME}-sa
      containers:
      - name: openldap
        image: docker.io/osixia/openldap:latest
        env:
        - name: LDAP_ADMIN_PASSWORD
          value: "${ADMIN_PASSWORD}"
        ports:
        - containerPort: 389
          name: ldap
EOF

echo "Configuring LDAP Service Account and SCC..."
oc create sa ${LDAP_NAME}-sa --dry-run=client -o yaml | oc apply -f -
# This is the critical step for LDAP permissions on OpenShift
oc adm policy add-scc-to-user anyuid -z ${LDAP_NAME}-sa

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

# --- 4. Create/Update AMQ Broker CR ---
echo "Applying AMQ Broker CR: ${BROKER_NAME}..."
cat <<EOF | oc apply -f -
apiVersion: broker.amq.io/v1beta1
kind: ActiveMQArtemis
metadata:
  name: ${BROKER_NAME}
spec:
  deploymentPlan:
    size: 2
    persistenceEnabled: false
    requireLogin: true
    messageMigration: false
    extraMounts:
      secrets:
        - ${JAAS_SECRET}
    managementRBACEnabled: true
    journalType: nio
    jolokiaAgentEnabled: false
  env:
    - name: JAVA_ARGS_APPEND
      value: "-Djava.security.auth.login.config=/etc/amq-secret-volume/${JAAS_SECRET}/login.config"
EOF

# --- 5. Verify ---
echo "Waiting for Broker rollout (this may take a few minutes)..."
oc rollout status statefulset/${BROKER_NAME}-ss

echo "Verifying LDAP connectivity from inside the cluster..."
oc exec -it deployment/${LDAP_NAME} -- ldapsearch -x -H ldap://localhost:389 -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w ${ADMIN_PASSWORD}

echo "-----------------------------------------------------------------------"
echo "Deployment Complete."
echo "Check broker logs for LDAP JAAS login attempts:"
echo "oc logs ${BROKER_NAME}-ss-0 | grep -i LDAP"
echo "-----------------------------------------------------------------------"
