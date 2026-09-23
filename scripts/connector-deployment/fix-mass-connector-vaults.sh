#!/bin/bash

# Script para configurar los secretos en los Vault del conector EDC
# Fecha: 2026-07-21
# Descripción: Configura los secretos necesarios en los Vault del conector EDC para MASS

set -e

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

echo "========================================"
echo "Configurando secretos en MASS Connector"
echo "========================================"

kubectl exec -n umbrella mass-edc-vault-0 -- \
  vault kv put secret/edc-wallet-secret content=changeme

kubectl exec -n umbrella mass-edc-vault-0 -- \
  vault kv put secret/tokenSignerPrivateKey content=changeme

kubectl exec -n umbrella mass-edc-vault-0 -- \
  vault kv put secret/tokenSignerPublicKey content=changeme

kubectl exec -n umbrella mass-edc-vault-0 -- \
  vault kv put secret/tokenEncryptionAesKey content=changeme

echo ""
echo "========================================"
echo "Verificando los secretos de Vault"
echo "========================================"

echo ""
echo "Secretos en MASS Connector:"
kubectl exec -n umbrella mass-edc-vault-0 -- vault kv list secret

echo ""
echo "✅ Configuración de secretos completada"
