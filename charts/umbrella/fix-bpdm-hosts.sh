#!/bin/bash
###############################################################################
# Fix BPDM Ingress Hosts
###############################################################################
# Este script actualiza los hosts de los ingress de BPDM para usar el dominio
# correcto (51.68.114.44.nip.io) en lugar del valor por defecto (tx.test)
#
# Uso: ./fix-bpdm-hosts.sh
###############################################################################

set -e

NAMESPACE="portal"
NEW_HOST="business-partners.51.68.114.44.nip.io"
OLD_HOST="business-partners.tx.test"

echo "=========================================="
echo "Fix BPDM Ingress Hosts"
echo "=========================================="
echo ""
echo "Namespace: $NAMESPACE"
echo "Nuevo host: $NEW_HOST"
echo ""

# Actualizar portal-bpdm-gate
echo "1. Actualizando portal-bpdm-gate..."
kubectl patch ingress -n "$NAMESPACE" portal-bpdm-gate --type=json -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$NEW_HOST\"}]"
echo "✓ portal-bpdm-gate actualizado"
echo ""

# Actualizar portal-bpdm-pool
echo "2. Actualizando portal-bpdm-pool..."
kubectl patch ingress -n "$NAMESPACE" portal-bpdm-pool --type=json -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$NEW_HOST\"}]"
echo "✓ portal-bpdm-pool actualizado"
echo ""

# Actualizar portal-bpdm-orchestrator
echo "3. Actualizando portal-bpdm-orchestrator..."
kubectl patch ingress -n "$NAMESPACE" portal-bpdm-orchestrator --type=json -p="[{\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$NEW_HOST\"}]"
echo "✓ portal-bpdm-orchestrator actualizado"
echo ""

echo "Esperando 5 segundos para que los cambios se apliquen..."
sleep 5

echo ""
echo "Verificando ingress actualizados:"
echo ""
kubectl get ingress -n "$NAMESPACE" | grep -i bpdm

echo ""
echo "=========================================="
echo "Ingress actualizados correctamente"
echo "=========================================="
echo ""
echo "Prueba BPDM Gate:"
echo "  curl http://$NEW_HOST/gate/api/catena/input/business-partners"
echo ""
echo "Ahora debes reintentar el proceso de onboarding ejecutando:"
echo "  kubectl delete pod -n portal -l app.kubernetes.io/name=portal-backend"
echo ""
