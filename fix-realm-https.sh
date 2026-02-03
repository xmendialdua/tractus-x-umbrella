#!/bin/bash
set -e

# Script para corregir requisito HTTPS en realms de SharedIdP
# Uso: ./fix-realm-https.sh idp1
#      ./fix-realm-https.sh idp2
# Fecha: 3 de Febrero de 2026

REALM_NAME=$1

if [ -z "$REALM_NAME" ]; then
    echo "❌ Error: Debes especificar el nombre del realm"
    echo "Uso: $0 <realm-name>"
    echo "Ejemplo: $0 idp1"
    exit 1
fi

echo "==========================================="
echo "Corrección de HTTPS Requirement en Realm"
echo "==========================================="
echo "Realm: $REALM_NAME"
echo "Namespace: portal"
echo ""

# Configurar KUBECONFIG
export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

echo "📡 Obteniendo token de administrador de Keycloak..."

# Obtener password de admin
ADMIN_PASSWORD=$(kubectl get secret -n portal portal-sharedidp -o jsonpath='{.data.admin-password}' | base64 -d)

if [ -z "$ADMIN_PASSWORD" ]; then
    echo "❌ Error: No se pudo obtener la contraseña de admin"
    exit 1
fi

# Obtener token de acceso
TOKEN=$(curl -s -X POST \
  "http://sharedidp.51.178.94.25.nip.io/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "❌ Error: No se pudo obtener el token de acceso"
    exit 1
fi

echo "✅ Token obtenido: ${TOKEN:0:30}..."
echo ""

echo "🔧 Verificando estado actual del realm..."

# Verificar estado actual
CURRENT_SSL=$(curl -s -X GET \
  "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/$REALM_NAME" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.sslRequired')

if [ "$CURRENT_SSL" == "null" ]; then
    echo "❌ Error: El realm '$REALM_NAME' no existe o no es accesible"
    exit 1
fi

echo "   Estado actual: sslRequired = $CURRENT_SSL"
echo ""

if [ "$CURRENT_SSL" == "NONE" ]; then
    echo "✅ El realm ya está configurado correctamente (sslRequired: NONE)"
    echo "   No se requiere ninguna acción"
    exit 0
fi

echo "🔨 Aplicando corrección: sslRequired = NONE ..."

# Aplicar corrección
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X PUT \
  "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/$REALM_NAME" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"realm\":\"$REALM_NAME\",\"sslRequired\":\"NONE\"}")

if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Error: La corrección falló (HTTP $HTTP_CODE)"
    exit 1
fi

echo "✅ Corrección aplicada exitosamente"
echo ""

echo "🔍 Verificando cambio..."
sleep 2

# Verificar que se aplicó
NEW_SSL=$(curl -s -X GET \
  "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/$REALM_NAME" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.sslRequired')

echo "   Nuevo estado: sslRequired = $NEW_SSL"
echo ""

if [ "$NEW_SSL" == "NONE" ]; then
    echo "✅ ¡Verificación exitosa! El realm '$REALM_NAME' está corregido"
    echo ""
    echo "El realm ahora acepta conexiones HTTP sin requisito de HTTPS"
else
    echo "⚠️  Advertencia: La verificación muestra sslRequired = $NEW_SSL"
    echo "   Se esperaba NONE. Puede ser necesario reintentar."
fi

echo ""
echo "==========================================="
echo "Proceso completado"
echo "==========================================="
