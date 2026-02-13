#!/bin/bash

# Script maestro para configurar completamente los conectores EDC
# Fecha: 2026-02-13
# Descripción: Ejecuta la configuración completa de Vault secrets y SSL trust

set -e

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

echo "╔═══════════════════════════════════════════════════════════╗"
echo "║   Configuración Completa de Conectores EDC Tractus-X     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Paso 1: Configurar secretos en Vault
echo "📦 PASO 1/3: Configurando secretos en Vault"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./fix-edc-connector-vaults.sh

# Paso 2: Configurar trust store con certificado CA
echo ""
echo "🔐 PASO 2/3: Configurando trust store con certificado CA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./fix-edc-connector-ssl-trust.sh

# Paso 3: Redesplegar conectores
echo ""
echo "🚀 PASO 3/3: Redesplegando conectores"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Buscar scripts de despliegue
if [ -f "./deploy-ikln-connector.sh" ]; then
    echo ""
    echo "   Redesplegando IKLN Connector..."
    ./deploy-ikln-connector.sh
else
    echo ""
    echo "   ⚠️  Script deploy-ikln-connector.sh no encontrado"
    echo "   Ejecuta manualmente:"
    echo "   helm upgrade ikln-edc ./charts/dataspace-connector-bundle -n umbrella -f ./charts/dataspace-connector-bundle/values-ikln-connector.yaml"
fi

if [ -f "./deploy-mass-connector.sh" ]; then
    echo ""
    echo "   Redesplegando MASS Connector..."
    ./deploy-mass-connector.sh
else
    echo ""
    echo "   ⚠️  Script deploy-mass-connector.sh no encontrado"
    echo "   Ejecuta manualmente:"
    echo "   helm upgrade mass-edc ./charts/dataspace-connector-bundle -n umbrella -f ./charts/dataspace-connector-bundle/values-mass-connector.yaml"
fi

# Esperar a que los pods estén listos
echo ""
echo "⏳ Esperando a que los pods estén listos..."
echo ""
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=tractusx-connector -n umbrella --timeout=300s

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║              ✅ CONFIGURACIÓN COMPLETADA                 ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "🔍 Verificación del despliegue:"
echo ""
kubectl get pods -n umbrella -l app.kubernetes.io/name=tractusx-connector

echo ""
echo "📋 Próximos pasos para verificar:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Ver logs de los controlplanes para verificar que no hay errores SSL:"
echo "   kubectl logs -n umbrella -l app.kubernetes.io/component=controlplane --tail=50"
echo ""
echo "2. Probar catalog query desde IKLN a MASS:"
echo "   curl -X POST https://edc-ikln-control.51.178.94.25.nip.io/management/v3/catalog/request \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -H \"X-Api-Key: ikln-api-key-change-in-production\" \\"
echo "     -d '{"
echo "       \"@context\": {\"@vocab\": \"https://w3id.org/edc/v0.0.1/ns/\"},"
echo "       \"@type\": \"CatalogRequest\","
echo "       \"counterPartyAddress\": \"https://edc-mass-control.51.178.94.25.nip.io/api/v1/dsp\","
echo "       \"counterPartyId\": \"BPNL00000000MASS\","
echo "       \"protocol\": \"dataspace-protocol-http\""
echo "     }'"
echo ""
echo "3. Verificar en la UI del EDC (https://edc-ikln-control.51.178.94.25.nip.io/)"
echo ""
