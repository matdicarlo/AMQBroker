#!/bin/bash
# Simulates pod failures for the AMQ broker HA setup

NAMESPACE="broker-f"

case "$1" in
  broker-0)
    echo "Simulating Publisher Broker failure..."
    oc delete pod broker-0-ss-0 -n $NAMESPACE
    echo "Observe: mqttpub will disconnect/reconnect. mqttsub will pause receiving until broker-0 recovers."
    ;;
  broker-1)
    echo "Simulating Subscriber Broker failure..."
    oc delete pod broker-1-ss-0 -n $NAMESPACE
    echo "Observe: mqttsub will disconnect. Upon recovery, it should receive all buffered messages."
    ;;
  both)
    echo "Simulating total cluster failure..."
    oc delete pod broker-0-ss-0 broker-1-ss-0 -n $NAMESPACE
    echo "Observe: Both clients disconnect. Full message flow resumes with no data loss after restart."
    ;;
  *)
    echo "Usage: $0 {broker-0|broker-1|both}"
    exit 1
    ;;
esac
