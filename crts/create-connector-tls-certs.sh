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

# Crear directorio temporal para certificados
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR"

echo "📁 Usando directorio temporal: $TEMP_DIR"
echo ""

# =============================================================================
# IKLN CONNECTOR
# =============================================================================

echo "🔧 Generando certificados para IKLN Connector..."

# Control Plane
echo "  → Control Plane (edc-ikln-control.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ikln-control-tls.key -out ikln-control-tls.crt \
  -subj "/CN=edc-ikln-control.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-ikln-control-tls \
  --cert=ikln-control-tls.crt --key=ikln-control-tls.key \
  -n ikln-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-ikln-control-tls creado en namespace ikln-connector"

# Data Plane
echo "  → Data Plane (edc-ikln-data.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout ikln-data-tls.key -out ikln-data-tls.crt \
  -subj "/CN=edc-ikln-data.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-ikln-data-tls \
  --cert=ikln-data-tls.crt --key=ikln-data-tls.key \
  -n ikln-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-ikln-data-tls creado en namespace ikln-connector"
echo ""

# =============================================================================
# MASS CONNECTOR
# =============================================================================

echo "🔧 Generando certificados para MASS Connector..."

# Control Plane
echo "  → Control Plane (edc-mass-control.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout mass-control-tls.key -out mass-control-tls.crt \
  -subj "/CN=edc-mass-control.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-mass-control-tls \
  --cert=mass-control-tls.crt --key=mass-control-tls.key \
  -n mass-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-mass-control-tls creado en namespace mass-connector"

# Data Plane
echo "  → Data Plane (edc-mass-data.51.178.94.25.nip.io)"
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout mass-data-tls.key -out mass-data-tls.crt \
  -subj "/CN=edc-mass-data.51.178.94.25.nip.io" \
  2>/dev/null

kubectl create secret tls edc-mass-data-tls \
  --cert=mass-data-tls.crt --key=mass-data-tls.key \
  -n mass-connector --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret edc-mass-data-tls creado en namespace mass-connector"
echo ""

# =============================================================================
# LIMPIEZA
# =============================================================================

cd - > /dev/null
rm -rf "$TEMP_DIR"

echo "🧹 Archivos temporales eliminados"
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
