#!/bin/bash

# Cargar las variables desde terraform.tfvars
APP_KEY="61101f573b889882"
APP_SECRET="af1fc01a6fd9dea065192be74a4a178d"
CONSUMER_KEY="4ae51736821878ed8538279d80c06e4a"

# Probar permisos básicos
echo "🔍 Verificando permisos de la API..."

# Test 1: Listar proyectos (GET)
echo -e "\n✓ Test GET /cloud/project:"
curl -X GET "https://eu.api.ovh.com/1.0/cloud/project" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY"

# Test 2: Obtener detalles del proyecto específico
echo -e "\n\n✓ Test GET /cloud/project/{serviceName}:"
curl -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY"

# Test 3: Verificar acceso a Kubernetes (el que está fallando)
echo -e "\n\n✓ Test GET /cloud/project/{serviceName}/kube:"
curl -X GET "https://eu.api.ovh.com/1.0/cloud/project/1628a7f46efb477f9f26ebdcdb2a3323/kube" \
  -H "X-Ovh-Application: $APP_KEY" \
  -H "X-Ovh-Consumer: $CONSUMER_KEY"

echo -e "\n\n✅ Si ves datos JSON, los permisos están OK"
echo "❌ Si ves 'Forbidden', necesitas regenerar el token"
