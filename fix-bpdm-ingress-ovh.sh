#!/bin/bash

###############################################################################
# Fix BPDM Ingress Configuration
###############################################################################
# Este script patchea los 3 Ingress de BPDM para configurar correctamente:
# - ingressClassName: nginx
# - host: business-partners.51.178.94.25.nip.io
#
# El subchart de BPDM crea los Ingress con valores por defecto incorrectos
# (business-partners.tx.test) que no son accesibles. Este script los corrige.
#
# Uso: ./fix-bpdm-ingress-ovh.sh
###############################################################################

set -e

NAMESPACE="portal"
HOST="business-partners.51.178.94.25.nip.io"
INGRESS_CLASS="nginx"

echo "=========================================="
echo "Fix BPDM Ingress - OVH Cluster"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Host: $HOST"
echo "IngressClassName: $INGRESS_CLASS"
echo ""

# Verificar que kubectl está configurado
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "❌ ERROR: No se puede acceder al namespace $NAMESPACE"
    echo "   Verifica que KUBECONFIG esté configurado correctamente"
    exit 1
fi

echo "Aplicando patches a los Ingress de BPDM..."
echo ""

# Patch 1: BPDM Pool
echo "📝 Actualizando portal-bpdm-pool..."
kubectl patch ingress portal-bpdm-pool -n "$NAMESPACE" --type=json -p="[
  {\"op\": \"add\", \"path\": \"/spec/ingressClassName\", \"value\": \"$INGRESS_CLASS\"},
  {\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$HOST\"}
]"

# Patch 2: BPDM Gate
echo "📝 Actualizando portal-bpdm-gate..."
kubectl patch ingress portal-bpdm-gate -n "$NAMESPACE" --type=json -p="[
  {\"op\": \"add\", \"path\": \"/spec/ingressClassName\", \"value\": \"$INGRESS_CLASS\"},
  {\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$HOST\"}
]"

# Patch 3: BPDM Orchestrator
echo "📝 Actualizando portal-bpdm-orchestrator..."
kubectl patch ingress portal-bpdm-orchestrator -n "$NAMESPACE" --type=json -p="[
  {\"op\": \"add\", \"path\": \"/spec/ingressClassName\", \"value\": \"$INGRESS_CLASS\"},
  {\"op\": \"replace\", \"path\": \"/spec/rules/0/host\", \"value\": \"$HOST\"}
]"

echo ""
echo "✅ Patches aplicados correctamente"
echo ""

# Verificación
echo "Verificando configuración de los Ingress:"
echo ""
kubectl get ingress -n "$NAMESPACE" | grep bpdm

echo ""
echo "=========================================="
echo "URLs de acceso:"
echo "=========================================="
echo "BPDM Pool:        http://$HOST/pool"
echo "BPDM Gate:        http://$HOST/gate"
echo "BPDM Orchestrator: http://$HOST/orchestrator"
echo ""
echo "Proceso completado"
echo "=========================================="
