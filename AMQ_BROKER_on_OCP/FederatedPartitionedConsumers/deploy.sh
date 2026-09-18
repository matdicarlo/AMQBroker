#!/bin/bash
set -e

NAMESPACE="broker-f"

echo "Setting project to $NAMESPACE..."
oc new-project $NAMESPACE 2>/dev/null || oc project $NAMESPACE

echo "Applying broker configurations..."
oc apply -f broker-0.yaml -n $NAMESPACE
oc apply -f broker-1.yaml -n $NAMESPACE

echo "Waiting for brokers to deploy..."
sleep 5 # Brief pause to allow the operator to process the CRs
oc wait --for=condition=Ready pod -l application=broker-0-app -n $NAMESPACE --timeout=300s
oc wait --for=condition=Ready pod -l application=broker-1-app -n $NAMESPACE --timeout=300s

echo "Building and deploying Publisher (mqttpub)..."
cd pub
./mvnw clean package -Dquarkus.kubernetes.deploy=true -Dquarkus.openshift.build-strategy=docker
cd ..

echo "Building and deploying Subscriber (mqttsub)..."
cd sub
./mvnw clean package -Dquarkus.kubernetes.deploy=true -Dquarkus.openshift.build-strategy=docker
cd ..

echo "Deployment complete! Check your pods with: oc get pods -n $NAMESPACE"
