#!/bin/bash

# Script para crear truststore Java con certificado CA
# Fecha: 2026-02-13
# Descripción: Crea un truststore Java que incluye el certificado CA interno

set -e

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

echo "========================================"
echo "Creando Java TrustStore con certificado CA"
echo "========================================"

# 1. Exportar el certificado CA raíz
echo ""
echo "1. Exportando certificado CA raíz..."
kubectl get secret root-secret -n umbrella -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/tractus-x-ca.crt

echo "   ✅ Certificado exportado a /tmp/tractus-x-ca.crt"

# Verificar el certificado
echo ""
echo "   Información del certificado:"
openssl x509 -in /tmp/tractus-x-ca.crt -text -noout | grep -A 2 "Subject:"

# 2. Obtener el truststore Java por defecto y agregar nuestro CA
echo ""
echo "2. Creando truststore Java personalizado..."

# Necesitamos una imagen Java para extraer el truststore por defecto
docker run --rm -v /tmp:/tmp eclipse-temurin:17-jre-alpine sh -c "
  cp \$JAVA_HOME/lib/security/cacerts /tmp/custom-cacerts
  chmod 644 /tmp/custom-cacerts
  keytool -importcert -noprompt -trustcacerts \
    -alias tractus-x-ca \
    -file /tmp/tractus-x-ca.crt \
    -keystore /tmp/custom-cacerts \
    -storepass changeit
  echo '✅ Certificado CA importado en truststore'
  keytool -list -keystore /tmp/custom-cacerts -storepass changeit -alias tractus-x-ca
"

echo ""
echo "3. Creando ConfigMap con truststore..."

# Crear ConfigMap con el truststore
kubectl create configmap edc-truststore \
  --from-file=cacerts=/tmp/custom-cacerts \
  -n umbrella \
  --dry-run=client -o yaml | kubectl apply -f -

echo "   ✅ ConfigMap 'edc-truststore' creado en namespace 'umbrella'"

# Verificar el ConfigMap
echo ""
echo "4. Verificando ConfigMap..."
kubectl get configmap edc-truststore -n umbrella
kubectl describe configmap edc-truststore -n umbrella | head -20

# Limpiar archivos temporales
rm -f /tmp/tractus-x-ca.crt /tmp/custom-cacerts

echo ""
echo "========================================"
echo "✅ TrustStore creado exitosamente"
echo "========================================"
echo ""
echo "El ConfigMap 'edc-truststore' contiene:"
echo "  - cacerts: TrustStore Java con el certificado CA interno"
echo ""
echo "Ahora puedes actualizar los archivos de valores de los conectores."
echo ""
