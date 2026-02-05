#!/bin/bash
set -e

echo "==========================================="
echo "Corrección de HTTPS en CentralIDP CX-Central"
echo "==========================================="

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

# Obtener password de admin
ADMIN_PASSWORD=$(kubectl get secret -n portal portal-centralidp -o jsonpath='{.data.admin-password}' | base64 -d)

echo "📡 Obteniendo token de CentralIDP..."

# Obtener token
TOKEN=$(curl -s -X POST \
  "http://centralidp.51.178.94.25.nip.io/auth/realms/master/protocol/openid-connect/token" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=$ADMIN_PASSWORD" \
  -d "grant_type=password" | jq -r '.access_token')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "❌ Error: No se pudo obtener el token"
    exit 1
fi

echo "✅ Token obtenido"

# Verificar estado actual
CURRENT_SSL=$(curl -s -X GET \
  "http://centralidp.51.178.94.25.nip.io/auth/admin/realms/CX-Central" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.sslRequired')

echo "   Estado actual CX-Central: sslRequired = $CURRENT_SSL"

if [ "$CURRENT_SSL" == "none" ] || [ "$CURRENT_SSL" == "NONE" ]; then
    echo "✅ Ya está configurado correctamente"
    exit 0
fi

# Aplicar corrección
echo "🔨 Aplicando corrección..."
curl -s -X PUT \
  "http://centralidp.51.178.94.25.nip.io/auth/admin/realms/CX-Central" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"realm":"CX-Central","sslRequired":"NONE"}' > /dev/null

echo "✅ Corrección aplicada"

# Verificar
NEW_SSL=$(curl -s -X GET \
  "http://centralidp.51.178.94.25.nip.io/auth/admin/realms/CX-Central" \
  -H "Authorization: Bearer $TOKEN" | jq -r '.sslRequired')

echo "   Nuevo estado: sslRequired = $NEW_SSL"
echo "==========================================="
