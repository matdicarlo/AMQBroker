How to have metrics separated by labels for Prometheus

# Requirements
- Operators installed: AMQ Broker Operator, Prometheus Operator
- Operand: AMQ Broker, Prometheus


# Configure rules for metrics

1. Create jmx-rules.yaml
~~~
lowercaseOutputName: true
lowercaseOutputLabelNames: true

includeObjectNames: ["org.apache.activemq.artemis:*"]

rules:
  - pattern: 'org.apache.activemq.artemis<broker="([^"]*)", component=addresses, address="([^"]*)"><>AddressSize'
    name: artemis_address_size
    type: GAUGE
    labels:
      broker: "$1"
      address: "$2"

  - pattern: 'org.apache.activemq.artemis<broker="([^"]*)", component=addresses, address="([^"]*)", subcomponent=queues, routing-type="([^"]*)", queue="([^"]*)"><>ConsumerCount'
    name: artemis_consumer_count
    type: GAUGE
    labels:
      broker: "$1"
      address: "$2"
      routing_type: "$3"
      queue: "$4"
~~~


2. Crete the secret
oc create secret generic jmx-metrics-config --from-file=config.yaml=jmx-rules.yaml

3. edit broker CR
~~~
apiVersion: broker.amq.io/v1beta1
kind: ActiveMQArtemis
metadata:
  creationTimestamp: "2026-05-27T11:02:08Z"
  generation: 2
  name: ex-aao
  namespace: broker
  resourceVersion: "1205852"
  uid: 89844556-51fb-4b3a-afd7-e664d0701e9b
spec:
  deploymentPlan:
    extraMounts:
      secrets:
      - jmx-metrics-config
    image: placeholder
    jolokiaAgentEnabled: false
    journalType: nio
    managementRBACEnabled: true
    messageMigration: false
    persistenceEnabled: false
    requireLogin: false
    size: 2
  env:
  - name: JAVA_ARGS_APPEND
    value: -javaagent:/opt/agents/prometheus.jar=9404:/amq/extra/secrets/jmx-metrics-config/config.yaml

~~~

# Test
~~~
oc exec -it ex-aao-ss-0 -- env JAVA_ARGS_APPEND="" amq-broker/bin/artemis producer --destination queue://samplequeue1 --message-count 50
oc exec -it ex-aao-ss-0 -- env JAVA_ARGS_APPEND="" amq-broker/bin/artemis producer --destination queue://samplequeue2 --message-count 100
oc exec -it ex-aao-ss-0 -- curl -s http://localhost:9404/metrics | grep samplequeue
artemis_address_size{address="samplequeue1",broker="amq-broker"} 57030.0
artemis_address_size{address="samplequeue2",broker="amq-broker"} 114080.0
artemis_consumer_count{address="samplequeue1",broker="amq-broker",queue="samplequeue1",routing_type="anycast"} 0.0
artemis_consumer_count{address="samplequeue2",broker="amq-broker",queue="samplequeue2",routing_type="anycast"} 0.0
~~~


# Configure PodMonitor
iA ServiceMonitor discovers scrape targets by looking for a Kubernetes Service object. Prometheus watches the Service, finds the underlying Pods linked to that Service (via Endpoints), and scrapes each Pod's IP directly.

~~~
oc apply -f cluster-monitorin-config.yaml
oc apply -f prometheus-pod-monitor.yaml
# verify
oc get pods -n openshift-user-workload-monitoring
# verify everything is running
oc get pods -n openshift-user-workload-monitoring

~~~



# Troubleshooot
~~~
oc logs deployment/prometheus-operator -n openshift-user-workload-monitoring -c prometheus-operator | grep -i artemis
# verify active targets
oc exec -it pod/prometheus-user-workload-0 -n openshift-user-workload-monitoring -c prometheus -- \
  curl -s http://localhost:9090/api/v1/targets?state=active
~~~



Summary Checklist of Your Entire Solution
The Application Layer (Your Initial Setup):

You created the jmx-rules.yaml to extract clean metric names and map variables into Prometheus labels (broker, address, queue, routing_type).

You mounted that file as a Secret in the broker namespace.

You appended the -javaagent to JAVA_ARGS_APPEND in the ActiveMQArtemis CR to spin up the metrics exporter inside the JVM on port 9404.

The Platform Layer (Your Step 1):

You created the cluster-monitoring-config ConfigMap in openshift-monitoring to tell Red Hat's underlying operator to wake up the openshift-user-workload-monitoring infrastructure.

The Discovery Layer (Your Step 2):

You applied the custom PodMonitor which queries the cluster for the pod label ActiveMQArtemis: ex-aao.

It fools the Kubernetes service discovery constraint by initiating the connection on a known port (8161) and immediately doing a surgical string replacement on the internal address string variable to hit your real metrics endpoint (9404).
