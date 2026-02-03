#!/bin/bash

###############################################################################
# Fix Self-Description Ingress Configuration
###############################################################################
# Este script patchea el Ingress de Self-Description Factory para añadir
# la ingressClassName necesaria para que el Ingress Controller de nginx
# lo procese correctamente.
#
# El subchart crea el Ingress sin ingressClassName, lo que hace que el
# Ingress Controller de nginx lo ignore.
#
# Uso: ./fix-selfdescription-ingress-ovh.sh
###############################################################################

set -e

NAMESPACE="portal"
INGRESS_CLASS="nginx"

echo "=========================================="
echo "Fix Self-Description Ingress - OVH Cluster"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "IngressClassName: $INGRESS_CLASS"
echo ""

# Verificar que kubectl está configurado
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "❌ ERROR: No se puede acceder al namespace $NAMESPACE"
    echo "   Verifica que KUBECONFIG esté configurado correctamente"
    exit 1
fi

echo "Aplicando patch al Ingress de Self-Description Factory..."
echo ""

# Patch: Self Description Factory
echo "📝 Actualizando portal-selfdescription..."
kubectl patch ingress portal-selfdescription -n "$NAMESPACE" --type=json -p="[
  {\"op\": \"add\", \"path\": \"/spec/ingressClassName\", \"value\": \"$INGRESS_CLASS\"}
]"

echo ""
echo "✅ Patch aplicado correctamente"
echo ""

# Verificación
echo "Verificando configuración del Ingress:"
echo ""
kubectl get ingress portal-selfdescription -n "$NAMESPACE"

echo ""
echo "=========================================="
echo "URL de acceso:"
echo "=========================================="
echo "Self-Description Factory: http://sdfactory.51.178.94.25.nip.io"
echo ""
echo "Proceso completado"
echo "=========================================="
