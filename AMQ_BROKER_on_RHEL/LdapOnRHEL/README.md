# Configure AMQ Broker authentication with LDAP on localhost

## LDAP
### Cleanup
~~~
# 1. Stop the service
sudo systemctl stop slapd

# 2. Wipe the config and data directories
sudo rm -rf /etc/openldap/slapd.d/*
sudo rm -rf /var/lib/ldap/*

# 3. Create a workspace for our scratch files
mkdir ldap-scratch
mkdir ldap-scratch/certs
cd ldap-scratch
~~~

### Create
~~~
# 1. Create the Certificate Authority (CA)
openssl req -new -x509 -nodes -days 3650 \
  -keyout certs/ca.key -out certs/ca.crt \
  -subj "/C=IT/ST=Abruzzo/L=Silvi/O=Artemis/CN=MyLocalCA"

# 2. Create the Server Key and Signing Request (CSR)
openssl req -new -nodes \
  -keyout certs/ldap.key -out certs/ldap.csr \
  -subj "/C=IT/ST=Abruzzo/L=Silvi/O=Artemis/CN=localhost"

# 3. Sign the Server Certificate with your new CA
openssl x509 -req -days 3650 -in certs/ldap.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/ldap.crt

# 4. Move them to the system location and set permissions
sudo mkdir -p /etc/openldap/certs
sudo cp certs/{ca.crt,ldap.crt,ldap.key} /etc/openldap/certs/
sudo chown ldap:ldap /etc/openldap/certs/*
sudo chmod 600 /etc/openldap/certs/ldap.key
~~~

### Create admin pwd
~~~
/usr/sbin/slappasswd -s admin
{SSHA}hQ0lQDBfWMFyCGSeGvTgsInc6/n8UtoX
~~~

### Create slapd.conf
~~~
# Global Settings
include         /etc/openldap/schema/core.schema
include         /etc/openldap/schema/cosine.schema
include         /etc/openldap/schema/inetorgperson.schema
include         /etc/openldap/schema/nis.schema

pidfile         /var/run/openldap/slapd.pid
argsfile        /var/run/openldap/slapd.args

# TLS Settings
TLSCACertificateFile    /etc/openldap/certs/ca.crt
TLSCertificateFile      /etc/openldap/certs/ldap.crt
TLSCertificateKeyFile   /etc/openldap/certs/ldap.key

# Config Database Permissions
database config
access to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage by * none

# Main Database (MDB)
database        mdb
suffix          "dc=redhat,dc=com"
rootdn          "cn=admin,dc=redhat,dc=com"
rootpw          admin
directory       /var/lib/ldap

index   objectClass eq,pres
index   ou,cn,mail,surname,givenname eq,pres,sub
~~~


### Validate and configure slapd.conf with slaptest
~~~
sudo slaptest -f slapd.conf -F /etc/openldap/slapd.d
~~~

### Set permissions
~~~
# 1. Fix ownership
sudo chown -R ldap:ldap /etc/openldap/slapd.d/
sudo chown -R ldap:ldap /var/lib/ldap/

# 2. Relax SELinux for the test
sudo setenforce 0

# 3. Start slapd
sudo systemctl start slapd
~~~

### Verify the handshake
~~~
openssl s_client -connect localhost:636 -showcerts
~~~

### populate users and roles in new data.ldif
~~~
dn: dc=redhat,dc=com
objectClass: top
objectClass: dcObject
objectClass: organization
o: Red Hat
dc: redhat

dn: ou=users,dc=redhat,dc=com
objectClass: organizationalUnit
ou: users

dn: ou=roles,dc=redhat,dc=com
objectClass: organizationalUnit
ou: roles

dn: uid=artemis,ou=users,dc=redhat,dc=com
objectClass: inetOrgPerson
uid: artemis
sn: Broker
cn: artemis
userPassword: password123

dn: cn=amq,ou=roles,dc=redhat,dc=com
objectClass: groupOfUniqueNames
cn: amq
uniqueMember: uid=artemis,ou=users,dc=redhat,dc=com
~~~

### add
~~~
ldapadd -x -D "cn=admin,dc=redhat,dc=com" -w admin -f data.ldif
# if already exists, run ldapdelete -x -D "cn=admin,dc=redhat,dc=com" -w admin -r "dc=redhat,dc=com"
~~~


### Restart slapd
~~~
sudo systemctl restart slapd
~~~


### Ldapsearch
~~~
ldapsearch -x -H ldap://localhost:389 \
  -D "cn=admin,dc=redhat,dc=com" \
  -w admin \
  -b "ou=users,dc=redhat,dc=com" \
  "(uid=artemis)"
# extended LDIF
#
# LDAPv3
# base <ou=users,dc=redhat,dc=com> with scope subtree
# filter: (uid=artemis)
# requesting: ALL
#

# artemis, users, redhat.com
dn: uid=artemis,ou=users,dc=redhat,dc=com
objectClass: inetOrgPerson
uid: artemis
sn: Broker
cn: artemis
userPassword:: cGFzc3dvcmQxMjM=

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1

~~~




# Broker (LDAP)
## login.config
~~~
activemq {
   org.apache.activemq.artemis.spi.core.security.jaas.LDAPLoginModule required
      debug=true
      reload=true
      initialContextFactory="com.sun.jndi.ldap.LdapCtxFactory"
      connectionURL="ldap://127.0.0.1:389"
      authentication="simple"
      userSearchSubtree=true
      connectionProtocol="s"
      connectionUsername="cn=admin,dc=redhat,dc=com"
      connectionPassword="admin"
      userBase="ou=users,dc=redhat,dc=com"
      userSearchMatching="(uid={0})"
      roleBase="ou=roles,dc=redhat,dc=com"
      roleName="cn"
      roleSearchMatching="(uniqueMember={0})"
      referral="ignore";
};

~~~


### Test the broker
~~~

./bin/artemis producer --user artemis --password password123 --url tcp://localhost:61616 --destination queue://testQueue --message-count 1
Connection brokerURL = tcp://localhost:61616
Producer ActiveMQQueue[testQueue], thread=0 Started to calculate elapsed time ...

Producer ActiveMQQueue[testQueue], thread=0 Produced: 1 messages
Producer ActiveMQQueue[testQueue], thread=0 Elapsed time in second : 0 s
Producer ActiveMQQueue[testQueue], thread=0 Elapsed time in milli second : 34 milli seconds

~~~






















# Broker

#### Create truststore
~~~
keytool -import -alias ldap-ca \
  -file host-certs/ca.crt \
  -keystore amq-ldap-truststore.p12 \
  -storetype PKCS12 \
  -storepass password123 \
  -noprompt
~~~


## etc/login.config
~~~
activemq {
   org.apache.activemq.artemis.spi.core.security.jaas.LDAPLoginModule required
      debug=true
      initialContextFactory="com.sun.jndi.ldap.LdapCtxFactory"
      connectionURL="ldaps://localhost:1636"
      connectionProtocol="ssl"
      authentication="simple"
      connectionUsername="uid=artemis,ou=users,dc=redhat,dc=com" 
      connectionPassword="password123"
      userBase="ou=users,dc=redhat,dc=com"
      userSearchMatching="(uid={0})"
      roleBase="ou=roles,dc=redhat,dc=com"
      roleName="cn"
      roleSearchMatching="(uniqueMember={0})"
      referral="ignore";
};
~~~

## Edit etc/artemis.profile
~~~
# Locate your JAVA_ARGS and append/update these:
-Djavax.net.ssl.trustStore=/home/mdicarlo/Programmi/GITHUB/AMQBroker/LdapOnRHEL/amq-ldap-truststore.p12 \
-Djavax.net.ssl.trustStorePassword=password123 \
-Djavax.net.ssl.trustStoreType=PKCS12 \
-Dcom.sun.jndi.ldap.object.disableEndpointIdentification=true \
-Dhawtio.roles=amq \
~~~




# Troubleshooting

## Show every connection attempt
~~~
sudo journalctl -u slapd -f
~~~

## Test with wrong password
~~~
./bin/artemis user list --user artemis --password WRONG_PASSWORD
~~~

