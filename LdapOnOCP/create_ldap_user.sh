oc exec -i deployment/openldap -- ldapadd -x -D "cn=admin,dc=example,dc=org" -w admin <<EOF
dn: ou=users,dc=example,dc=org
objectClass: organizationalUnit
ou: users

dn: uid=artemis,ou=users,dc=example,dc=org
objectClass: inetOrgPerson
cn: Artemis User
sn: User
uid: artemis
userPassword: password

dn: ou=groups,dc=example,dc=org
objectClass: organizationalUnit
ou: groups

dn: cn=amq,ou=groups,dc=example,dc=org
objectClass: groupOfUniqueNames
cn: amq
uniqueMember: uid=artemis,ou=users,dc=example,dc=org
EOF
