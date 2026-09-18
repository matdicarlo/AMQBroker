# HA with Federation and Partitioned Consumers (using Connection Router and Hash Module)

This project implements a High Availability (HA) MQTT architecture using AMQ Broker (ActiveMQ Artemis) and Camel Quarkus. It demonstrates how to federate brokers and partition MQTT consumers using a connection router and a consistent hash modulo policy.

## Architecture Overview
The implementation consists of a two-node AMQ Broker cluster (`broker-0` and `broker-1`) running in the `broker-f` namespace. To maintain MQTT session state reliably across the cluster, a connection router is placed in front of the MQTT acceptors. Client connections are routed to a specific broker node based on their `CLIENT_ID`.

## Broker Configurations
Both brokers use `ON_DEMAND` message load balancing and static connectors to form a cluster. 
* **Connection Router (`client-router`)**: Configured directly on the MQTT acceptor (port 1883).
* **Routing Policy**: Uses `keyType=CLIENT_ID` combined with the `CONSISTENT_HASH_MODULO` policy configuration.
* **Modulo**: Set to `MODULO=2` to divide connections between the two nodes.
* **Local Target Filters**: 
  * `broker-0` handles connections matching `localTargetFilter=NULL|0|-0`.
  * `broker-1` handles connections matching `localTargetFilter=1|-1`.

## Publisher Application (`mqttpub`)
The publisher is a Camel Quarkus application that continuously generates messages.
* Uses a Camel timer and SEDA queue to generate a payload with a custom `MQPERF_counter` and `MQPERF_time` stored in the MQTT5 User Properties.
* Connects directly to `broker-0` via `tcp://broker-0-mqtt-0-svc.broker-f.svc.cluster.local:1883`.
* Publishes to `testqueue` with QoS 1, `cleanStart=false`, and a `sessionExpiryInterval` of `4294967295`.

## Subscriber Application (`mqttsub`)
The subscriber is a Camel Quarkus application that consumes the routed messages.
* Connects to `broker-1` via `tcp://broker-1-mqtt-0-svc.broker-f.svc.cluster.local:1883`.
* Uses a fixed Client ID (`mqtt-subscriber-fixed-id`) to ensure the connection router always hashes it to the same broker node.
* Subscribes to `testqueue` with QoS 1, `cleanStart=false`, and an effective session expiry interval of `4294967295` to maintain stateful subscriptions.