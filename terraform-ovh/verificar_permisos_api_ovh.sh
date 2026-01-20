#!/bin/bash
# filepath: \\wsl.localhost\Ubuntu\home\xmendialdua\projects\assembly\tractus-x-umbrella\terraform-ovh\check_api_key.sh

# Script para verificar permisos de la API de OVH

# Cargar credenciales desde terraform.tfvars
if [ -f "terraform.tfvars" ]; then
    APP_KEY=$(grep 'ovh_application_key' terraform.tfvars | cut -d'"' -f2)
    CONSUMER_KEY=$(grep 'ovh_consumer_key' terraform.tfvars | cut -d'"' -f2)
else
    echo "❌ No se encontró terraform.tfvars"
    exit 1
fi

echo "🔍 Verificando permisos de tu API Key..."
echo "Application Key: $APP_KEY"
echo ""

# Test 1: Listar proyectos cloud
echo "═══════════════════════════════════════════════════════════"
echo "📋 Test 1: GET /cloud/project (listar proyectos)"
echo "═══════════════════════════════════════════════════════════"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Permiso GET /cloud/project - OK"
    echo "Proyectos encontrados:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
    echo "❌ Permiso GET /cloud/project - HTTP $HTTP_CODE"
    echo "$BODY"
fi

# Test 2: Obtener info del proyecto específico
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📋 Test 2: GET /cloud/project/{serviceName}"
echo "═══════════════════════════════════════════════════════════"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Permiso GET /cloud/project/{id} - OK"
    echo "Información del proyecto:"
    echo "$BODY" | jq '{description, status}' 2>/dev/null || echo "$BODY"
else
    echo "❌ Permiso GET /cloud/project/{id} - HTTP $HTTP_CODE"
    echo "$BODY"
fi

# Test 3: Verificar acceso a endpoints de Kubernetes
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📋 Test 3: GET /cloud/project/{serviceName}/kube"
echo "═══════════════════════════════════════════════════════════"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323/kube" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Permiso GET /cloud/.../kube - OK"
    echo "Clusters existentes:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ Permiso GET /cloud/.../kube - FORBIDDEN"
    echo "⚠️  Tu API Key NO tiene permisos para acceder a Kubernetes"
else
    echo "⚠️  Permiso GET /cloud/.../kube - HTTP $HTTP_CODE"
    echo "$BODY"
fi

# Test 4: Verificar regiones disponibles para Kubernetes
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📋 Test 4: GET /cloud/project/{serviceName}/capabilities/kube/regions"
echo "═══════════════════════════════════════════════════════════"

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323/capabilities/kube/regions" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Permiso GET /cloud/.../capabilities/kube/regions - OK"
    echo "Regiones disponibles para Kubernetes:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
else
    echo "❌ Permiso GET /cloud/.../capabilities/kube/regions - HTTP $HTTP_CODE"
    echo "$BODY"
fi

# Resumen final
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "📊 RESUMEN DE DIAGNÓSTICO"
echo "═══════════════════════════════════════════════════════════"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Tu API Key tiene permisos de LECTURA (GET)"
    echo ""
    echo "⚠️  IMPORTANTE:"
    echo "   Si terraform apply falla con error 403, significa que"
    echo "   tu API Key tiene GET pero NO tiene POST/PUT/DELETE"
    echo ""
    echo "🔧 SOLUCIÓN:"
    echo "   Ve a: https://api.ovh.com/createToken/"
    echo "   Asegúrate de marcar TODAS estas opciones:"
    echo "   ✓ GET    /cloud/*"
    echo "   ✓ POST   /cloud/*"
    echo "   ✓ PUT    /cloud/*"
    echo "   ✓ DELETE /cloud/*"
else
    echo "❌ Tu API Key NO tiene los permisos necesarios"
    echo ""
    echo "🔧 SOLUCIÓN:"
    echo "   1. Ve a: https://api.ovh.com/createToken/"
    echo "   2. Marca TODAS estas opciones:"
    echo "      ✓ GET    /cloud/*"
    echo "      ✓ POST   /cloud/*"
    echo "      ✓ PUT    /cloud/*"
    echo "      ✓ DELETE /cloud/*"
    echo "      ✓ GET    /order/*"
    echo "      ✓ POST   /order/*"
    echo "   3. Actualiza terraform.tfvars con las nuevas credenciales"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"