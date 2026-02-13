#!/bin/bash

# Script para configurar los conectores EDC para confiar en el certificado CA interno
# Fecha: 2026-02-13
# Descripción: Crea ConfigMaps con el certificado CA y los monta en los pods EDC

set -e

export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

echo "========================================"
echo "Configurando Trust Store para EDC Connectors"
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

# 2. Crear ConfigMap con el certificado CA en el namespace umbrella
echo ""
echo "2. Creando ConfigMap con certificado CA..."

kubectl create configmap edc-ca-cert \
  --from-file=ca.crt=/tmp/tractus-x-ca.crt \
  -n umbrella \
  --dry-run=client -o yaml | kubectl apply -f -

echo "   ✅ ConfigMap 'edc-ca-cert' creado en namespace 'umbrella'"

# 3. Verificar el ConfigMap
echo ""
echo "3. Verificando ConfigMap..."
kubectl get configmap edc-ca-cert -n umbrella

echo ""
echo "========================================"
echo "✅ Configuración de Trust Store completada"
echo "========================================"
echo ""
echo "SIGUIENTES PASOS:"
echo "1. Actualizar los archivos de configuración de los conectores:"
echo "   - charts/dataspace-connector-bundle/values-ikln-connector.yaml"
echo "   - charts/dataspace-connector-bundle/values-mass-connector.yaml"
echo ""
echo "2. Añadir la siguiente configuración en ambos archivos (ya en controlplane y dataplane):"
echo ""
echo "   controlplane:"
echo "     extraVolumes:"
echo "       - name: ca-cert"
echo "         configMap:"
echo "           name: edc-ca-cert"
echo "     extraVolumeMounts:"
echo "       - name: ca-cert"
echo "         mountPath: /tmp/ca-certificates"
echo "         readOnly: true"
echo "     env:"
echo "       JAVA_TOOL_OPTIONS: >"
echo "         -Djavax.net.ssl.trustStore=/tmp/cacerts"
echo "         -Djavax.net.ssl.trustStorePassword=changeit"
echo "     initContainers:"
echo "       - name: import-ca-cert"
echo "         image: eclipse-temurin:17-jre-alpine"
echo "         command:"
echo "           - sh"
echo "           - -c"
echo "           - |"
echo "             cp \$JAVA_HOME/lib/security/cacerts /tmp/cacerts"
echo "             chmod 644 /tmp/cacerts"
echo "             keytool -importcert -noprompt -trustcacerts \\"
echo "               -alias tractus-x-ca \\"
echo "               -file /tmp/ca-certificates/ca.crt \\"
echo "               -keystore /tmp/cacerts \\"
echo "               -storepass changeit"
echo "         volumeMounts:"
echo "           - name: ca-cert"
echo "             mountPath: /tmp/ca-certificates"
echo "             readOnly: true"
echo "           - name: truststore"
echo "             mountPath: /tmp"
echo ""
echo "     extraVolumes:"
echo "       - name: truststore"
echo "         emptyDir: {}"
echo ""
echo "3. Lo mismo para dataplane (cambiar 'controlplane:' por 'dataplane:')"
echo ""
echo "4. Redesplegar los conectores:"
echo "   ./deploy-ikln-connector.sh"
echo "   ./deploy-mass-connector.sh"
echo ""
