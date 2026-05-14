# Environment
OCP
AMQ Broker Operator
AMQ Broker 7.14
docker.io/osixia/openldap

# AMQ Broker on OCP - LDAP 

### 1. Deploy a local OpenLDAP server
~~~
oc new-app --name openldap ALLOW_EMPTY_PASSWORD=yes --image docker.io/osixia/openldap:latest
~~~

Create a service account named openldap-sa
~~~
oc create sa openldap-sa

#Assign the anyuid SCC to the openldap-sa service account.
oc adm policy add-scc-to-user anyuid -z openldap-sa

#Assign service account to deployment
oc set serviceaccount deployment/openldap openldap-sa

#Verify
oc get deploy/openldap -o yaml | oc adm policy scc-subject-review -f -

#log into the container
oc exec -it pods/<ldap-pod> bash

#execute a ldapsearch
ldapsearch -x -H ldap://localhost:389 -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin
~~~


### 2. Create a local JAAS module file: login.config
~~~
activemq {
   org.apache.activemq.artemis.spi.core.security.jaas.LDAPLoginModule sufficient
       debug=true
       initialContextFactory="com.sun.jndi.ldap.LdapCtxFactory"
       connectionURL="ldap://openldap:389"
       connectionUsername="cn=admin,dc=example,dc=org"
       connectionPassword="password0"
       authentication="simple"
       userBase="dc=example,dc=org"
       userSearchMatching="(uid={0})"
       userSearchSubtree=true
       roleBase="dc=example,dc=org"
       roleName="cn"
       roleSearchMatching="(uniqueMember={0})"
       roleSearchSubtree=false;
};
~~~

### 3. Create the OpenShift secret
~~~
oc create secret generic custom-jaas-config --from-file=login.config --dry-run=client -o yaml | oc apply -f -
~~~

### 4. Update the AMQ Broker Custom Resource
~~~
oc edit ActiveMQArtemis ex-aao

spec:
  deploymentPlan:
    # Ensure this secret is mounted
    extraMounts:
      secrets:
        - custom-jaas-config
    requireLogin: true
  env:
    - name: JAVA_ARGS_APPEND
      value: "-Djava.security.auth.login.config=/etc/amq-secret-volume/custom-jaas-config/login.config"

~~~

### 5. Verify and test
~~~
$oc logs -f ex-aao-ss-0 | grep -i ldap
Defaulted container "ex-aao-container" out of: ex-aao-container, ex-aao-container-init (init)
2026-05-06 08:00:56,441 INFO  [org.apache.activemq.artemis.core.server] AMQ221020: Started EPOLL Acceptor at ex-aao-ss-0.ex-aao-hdls-svc.amq-broker-ldap.svc.cluster.local:61616 for protocols [CORE]
2026-05-06 08:00:56,950 INFO  [org.apache.activemq.artemis] AMQ241001: HTTP Server started at http://ex-aao-ss-0.ex-aao-hdls-svc.amq-broker-ldap.svc.cluster.local:8161
2026-05-06 08:00:56,950 INFO  [org.apache.activemq.artemis] AMQ241002: Artemis Jolokia REST API available at http://ex-aao-ss-0.ex-aao-hdls-svc.amq-broker-ldap.svc.cluster.local:8161/console/jolokia
2026-05-06 08:00:56,950 INFO  [org.apache.activemq.artemis] AMQ241004: Artemis Console available at http://ex-aao-ss-0.ex-aao-hdls-svc.amq-broker-ldap.svc.cluster.local:8161/console
2026-05-06 08:01:45,547 INFO  [org.apache.activemq.artemis.core.server] AMQ221027: Bridge ClusterConnectionBridge@4dd06bd6 [name=$.artemis.internal.sf.my-cluster.a6e7717c-4921-11f1-9bb1-0a580a81002c, queue=QueueImpl[name=$.artemis.internal.sf.my-cluster.a6e7717c-4921-11f1-9bb1-0a580a81002c, postOffice=PostOfficeImpl [server=ActiveMQServerImpl::name=amq-broker], temp=false]@61ac7b7a targetConnector=ServerLocatorImpl (identity=(Cluster-connection-bridge::ClusterConnectionBridge@4dd06bd6 [name=$.artemis.internal.sf.my-cluster.a6e7717c-4921-11f1-9bb1-0a580a81002c, queue=QueueImpl[name=$.artemis.internal.sf.my-cluster.a6e7717c-4921-11f1-9bb1-0a580a81002c, postOffice=PostOfficeImpl [server=ActiveMQServerImpl::name=amq-broker], temp=false]@61ac7b7a targetConnector=ServerLocatorImpl [initialConnectors=[TransportConfiguration(name=artemis, factory=org-apache-activemq-artemis-core-remoting-impl-netty-NettyConnectorFactory)?port=61616&host=ex-aao-ss-1-ex-aao-hdls-svc-amq-broker-ldap-svc-cluster-local], discoveryGroupConfiguration=null]]::ClusterConnectionImpl@1708084589[nodeUUID=b48ca386-4921-11f1-b06b-0a580a800028, connector=TransportConfiguration(name=artemis, factory=org-apache-activemq-artemis-core-remoting-impl-netty-NettyConnectorFactory)?port=61616&host=ex-aao-ss-0-ex-aao-hdls-svc-amq-broker-ldap-svc-cluster-local, address=, server=ActiveMQServerImpl::name=amq-broker])) [initialConnectors=[TransportConfiguration(name=artemis, factory=org-apache-activemq-artemis-core-remoting-impl-netty-NettyConnectorFactory)?port=61616&host=ex-aao-ss-1-ex-aao-hdls-svc-amq-broker-ldap-svc-cluster-local], discoveryGroupConfiguration=null]] is connected



$oc get all
Warning: apps.openshift.io/v1 DeploymentConfig is deprecated in v4.14+, unavailable in v4.10000+
NAME                            READY   STATUS    RESTARTS   AGE
pod/ex-aao-ss-0                 1/1     Running   0          18s
pod/ex-aao-ss-1                 1/1     Running   0          40s
pod/openldap-64d7d544bc-6hv8q   1/1     Running   0          9m36s

NAME                      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                AGE
service/ex-aao-hdls-svc   ClusterIP   None            <none>        7800/TCP,8161/TCP,8778/TCP,61616/TCP   73s
service/ex-aao-ping-svc   ClusterIP   None            <none>        8888/TCP                               73s
service/openldap          ClusterIP   172.30.254.56   <none>        389/TCP,636/TCP                        12m

NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/openldap   1/1     1            1           12m

NAME                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/openldap-5c8dd8545f   0         0         0       12m
replicaset.apps/openldap-64d7d544bc   1         1         1       9m36s
replicaset.apps/openldap-f5486b99c    0         0         0       12m

NAME                         READY   AGE
statefulset.apps/ex-aao-ss   2/2     74s

NAME                                      IMAGE REPOSITORY                                                            TAGS     UPDATED
imagestream.image.openshift.io/openldap   image-registry.openshift-image-registry.svc:5000/amq-broker-ldap/openldap   latest   12 minutes ago

oc exec -it deployment/openldap -- ldapsearch -x -H ldap://localhost:389 -b dc=example,dc=org -D "cn=admin,dc=example,dc=org" -w admin
# extended LDIF
#
# LDAPv3
# base <dc=example,dc=org> with scope subtree
# filter: (objectclass=*)
# requesting: ALL
#

# example.org
dn: dc=example,dc=org
objectClass: top
objectClass: dcObject
objectClass: organization
o: Example Inc.
dc: example

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1
E0506 10:05:32.460891  254969 v3.go:79] EOF
~~~


