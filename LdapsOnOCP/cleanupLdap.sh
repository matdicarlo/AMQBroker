# 1. Delete the current broken deployment
oc delete all -l app=openldap

# 2. Deploy with the correct Osixia environment variables
oc new-app --name openldap \
  --image=docker.io/osixia/openldap:latest \
  -e LDAP_ADMIN_PASSWORD=admin \
  -e LDAP_DOMAIN=example.org \
  -e LDAP_ORGANISATION="MyLab"

# 3. Re-apply the Service Account and SCC (since we deleted the deployment)
oc set serviceaccount deployment/openldap openldap-sa

# 4. Wait for it to become ready
oc rollout status deployment/openldap
