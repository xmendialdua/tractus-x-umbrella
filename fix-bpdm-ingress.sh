#!/bin/bash
set -e

# Script para corregir Ingress de BPDM
# Añade ingressClassName: nginx y cambia host a business-partners.51.68.114.44.nip.io
# Fecha: 27 de Enero de 2026
# Uso: ./fix-bpdm-ingress.sh

NAMESPACE="portal"
HOST="business-partners.51.68.114.44.nip.io"

echo "=== Corrección de Ingress BPDM ==="
echo "Namespace: $NAMESPACE"
echo "Host: $HOST"
echo ""

# Función para patchear un ingress
patch_ingress() {
  local name=$1
  echo "Parcheando $name..."
  
  kubectl patch ingress "$name" -n "$NAMESPACE" --type=json -p='[
    {"op": "add", "path": "/spec/ingressClassName", "value": "nginx"},
    {"op": "replace", "path": "/spec/rules/0/host", "value": "'"$HOST"'"}
  ]'
  
  if [ $? -eq 0 ]; then
    echo "✅ $name parcheado correctamente"
  else
    echo "❌ Error al parchear $name"
    exit 1
  fi
  echo ""
}

# Parchear los 3 Ingress de BPDM
patch_ingress "portal-bpdm-pool"
patch_ingress "portal-bpdm-gate"
patch_ingress "portal-bpdm-orchestrator"

echo "=== Verificando resultado ==="
kubectl get ingress -n "$NAMESPACE" | grep bpdm
echo ""

echo "=== Probando conectividad ==="
echo -n "Pool health check: "
curl -s -o /dev/null -w "%{http_code}" "http://$HOST/pool/actuator/health"
echo ""

echo -n "Gate health check: "
curl -s -o /dev/null -w "%{http_code}" "http://$HOST/gate/actuator/health"
echo ""

echo ""
echo "✅ Proceso completado exitosamente"
