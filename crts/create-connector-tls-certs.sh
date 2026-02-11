#!/bin/bash
###############################################################
# Script para crear certificados TLS auto-firmados
# para los conectores IKLN y MASS
#
# Crea 4 secretos TLS:
# - edc-ikln-control-tls (namespace: ikln-connector)
# - edc-ikln-data-tls (namespace: ikln-connector)
# - edc-mass-control-tls (namespace: mass-connector)
# - edc-mass-data-tls (namespace: mass-connector)
#
# Uso: ./create-connector-tls-certs.sh
###############################################################

set -e

echo "🔐 Creando certificados TLS auto-firmados para conectores..."
echo ""

# Obtener el directorio del script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Crear subcarpetas para organizar certificados
echo "📁 Creando estructura de directorios..."
mkdir -p "$SCRIPT_DIR/edc-ikln-control-plane"
mkdir -p "$SCRIPT_DIR/edc-ikln-data-plane"
mkdir -p "$SCRIPT_DIR/edc-mass-control-plane"
mkdir -p "$SCRIPT_DIR/edc-mass-data-plane"
echo ""

# =============================================================================
# IKLN CONNECTOR
# =============================================================================

echo "🔧 Generando certificados para IKLN Connector..."

# Control Plane
echo "  → Control Plane (edc-ikln-control.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SCRIPT_DIR/edc-ikln-control-plane/tls.key" \
  -out "$SCRIPT_DIR/edc-ikln-control-plane/tls.crt" \
  -subj "/CN=edc-ikln-control.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-ikln-control-tls \
  --cert="$SCRIPT_DIR/edc-ikln-control-plane/tls.crt" \
  --key="$SCRIPT_DIR/edc-ikln-control-plane/tls.key" \
  -n ikln-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-ikln-control-tls creado en namespace ikln-connector"
echo "  ✓ Certificados guardados en: edc-ikln-control-plane/"

# Data Plane
echo "  → Data Plane (edc-ikln-data.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SCRIPT_DIR/edc-ikln-data-plane/tls.key" \
  -out "$SCRIPT_DIR/edc-ikln-data-plane/tls.crt" \
  -subj "/CN=edc-ikln-data.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-ikln-data-tls \
  --cert="$SCRIPT_DIR/edc-ikln-data-plane/tls.crt" \
  --key="$SCRIPT_DIR/edc-ikln-data-plane/tls.key" \
  -n ikln-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-ikln-data-tls creado en namespace ikln-connector"
echo "  ✓ Certificados guardados en: edc-ikln-data-plane/"
echo ""

# =============================================================================
# MASS CONNECTOR
# =============================================================================

echo "🔧 Generando certificados para MASS Connector..."

# Control Plane
echo "  → Control Plane (edc-mass-control.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SCRIPT_DIR/edc-mass-control-plane/tls.key" \
  -out "$SCRIPT_DIR/edc-mass-control-plane/tls.crt" \
  -subj "/CN=edc-mass-control.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-mass-control-tls \
  --cert="$SCRIPT_DIR/edc-mass-control-plane/tls.crt" \
  --key="$SCRIPT_DIR/edc-mass-control-plane/tls.key" \
  -n mass-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-mass-control-tls creado en namespace mass-connector"
echo "  ✓ Certificados guardados en: edc-mass-control-plane/"

# Data Plane
echo "  → Data Plane (edc-mass-data.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$SCRIPT_DIR/edc-mass-data-plane/tls.key" \
  -out "$SCRIPT_DIR/edc-mass-data-plane/tls.crt" \
  -subj "/CN=edc-mass-data.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-mass-data-tls \
  --cert="$SCRIPT_DIR/edc-mass-data-plane/tls.crt" \
  --key="$SCRIPT_DIR/edc-mass-data-plane/tls.key" \
  -n mass-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-mass-data-tls creado en namespace mass-connector"
echo "  ✓ Certificados guardados en: edc-mass-data-plane/"
echo ""

# =============================================================================
# RESUMEN
# =============================================================================

echo "📋 Estructura de certificados creada:"
echo "   crts/"
echo "   ├── edc-ikln-control-plane/"
echo "   │   ├── tls.crt"
echo "   │   └── tls.key"
echo "   ├── edc-ikln-data-plane/"
echo "   │   ├── tls.crt"
echo "   │   └── tls.key"
echo "   ├── edc-mass-control-plane/"
echo "   │   ├── tls.crt"
echo "   │   └── tls.key"
echo "   └── edc-mass-data-plane/"
echo "       ├── tls.crt"
echo "       └── tls.key"
echo ""

# =============================================================================
# VERIFICACIÓN
# =============================================================================

echo "✅ Certificados TLS creados exitosamente!"
echo ""
echo "📋 Verificar secretos creados:"
echo "  kubectl get secrets -n ikln-connector | grep tls"
echo "  kubectl get secrets -n mass-connector | grep tls"
echo ""
echo "⚠️  NOTA: Estos son certificados auto-firmados para desarrollo/testing."
echo "   Para producción, considera usar cert-manager con Let's Encrypt."
echo ""
