#!/bin/bash
# Script para generar ConfigMaps con realms customizados
# Uso: ./generate-realm-configmap.sh 51.83.111.178 .nip.io

set -e

LOAD_BALANCER_IP=${1:-"51.83.111.178"}
DNS_SUFFIX=${2:-".nip.io"}
TARGET_DOMAIN="${LOAD_BALANCER_IP}${DNS_SUFFIX}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../" && pwd)"
TEMP_DIR="/tmp/keycloak-realms-custom"

echo "================================================"
echo "Generando realms customizados para Keycloak"
echo "================================================"
echo "IP LoadBalancer: $LOAD_BALANCER_IP"
echo "DNS Suffix: $DNS_SUFFIX"
echo "Target Domain: $TARGET_DOMAIN"
echo ""

# Crear directorio temporal
rm -rf "$TEMP_DIR"
mkdir -p "$TEMP_DIR/centralidp"
mkdir -p "$TEMP_DIR/sharedidp"

# Generar JSON para Central IDP
echo "Generando CX-Central-realm.json..."
sed "s/tx\.test/${TARGET_DOMAIN}/g" \
    "$PROJECT_ROOT/init-container/iam/centralidp/CX-Central-realm.json" \
    > "$TEMP_DIR/centralidp/CX-Central-realm.json"

echo "Generando CX-Central-users-0.json..."
sed "s/tx\.test/${TARGET_DOMAIN}/g" \
    "$PROJECT_ROOT/init-container/iam/centralidp/CX-Central-users-0.json" \
    > "$TEMP_DIR/centralidp/CX-Central-users-0.json"

# Verificar que se generaron correctamente
echo ""
echo "Verificando archivos generados..."
if grep -q "tx\.test" "$TEMP_DIR/centralidp/"*.json; then
    echo "❌ ERROR: Todavía hay referencias a tx.test en los archivos generados"
    exit 1
fi

echo "✅ Archivos generados correctamente"
echo ""
echo "Archivos generados en: $TEMP_DIR"
ls -lh "$TEMP_DIR/centralidp/"

echo ""
echo "Verificando número de cambios realizados..."
CHANGES_REALM=$(grep -o "${TARGET_DOMAIN}" "$TEMP_DIR/centralidp/CX-Central-realm.json" | wc -l)
CHANGES_USERS=$(grep -o "${TARGET_DOMAIN}" "$TEMP_DIR/centralidp/CX-Central-users-0.json" | wc -l)
echo "  - CX-Central-realm.json: $CHANGES_REALM ocurrencias"
echo "  - CX-Central-users-0.json: $CHANGES_USERS ocurrencias"

echo ""
echo "================================================"
echo "Para aplicar, ejecuta:"
echo "================================================"
echo "kubectl create configmap centralidp-realm-custom \\"
echo "  --from-file=$TEMP_DIR/centralidp/ \\"
echo "  -n portal \\"
echo "  --dry-run=client -o yaml | kubectl apply -f -"
echo ""
