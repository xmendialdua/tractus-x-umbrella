#!/bin/bash

# Script para verificar permisos de la API de OVH

APP_KEY="61101f573b889882"
CONSUMER_KEY="4ae51736821878ed8538279d80c06e4a"

echo "🔍 Verificando permisos de tu API Key..."
echo ""

# Test: Acceso a información del proyecto
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ GET /cloud/project - OK"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ GET /cloud/project - FORBIDDEN (sin permisos)"
else
    echo "⚠️  GET /cloud/project - HTTP $HTTP_CODE"
fi

echo ""
echo "Respuesta:"
echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"

echo ""
echo "----------------------------------------"
echo "Si ves 403 Forbidden, necesitas regenerar el token en:"
echo "https://api.ovh.com/createToken/"
