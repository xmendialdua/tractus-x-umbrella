#!/bin/bash

# Script para obtener kubeconfig directamente de OVH API

APP_KEY=$(grep 'ovh_application_key' terraform.tfvars | cut -d'"' -f2)
CONSUMER_KEY=$(grep 'ovh_consumer_key' terraform.tfvars | cut -d'"' -f2)
PROJECT_ID="1628a7f46efb477f9f26ebdcdb2a3323"

# Obtener el ID del cluster
CLUSTER_ID=$(curl -s \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project/${PROJECT_ID}/kube" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY" | jq -r '.[0]')

echo "Cluster ID: $CLUSTER_ID"

# Obtener el kubeconfig
curl -s \
  -X POST "https://eu.api.ovh.com/1.0/cloud/project/${PROJECT_ID}/kube/${CLUSTER_ID}/kubeconfig" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY" \
  -H "Content-Type: application/json" \
  -d '{}' | jq -r '.content' | base64 -d > kubeconfig.yaml

echo "✅ Kubeconfig guardado en kubeconfig.yaml"
