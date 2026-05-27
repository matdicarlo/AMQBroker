How to have metrics separated by labels for Prometheus

# Configure

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
