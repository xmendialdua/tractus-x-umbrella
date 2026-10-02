#!/bin/bash
# Script para automatizar todo el proceso de actualización de URLs
# Este script:
# 1. Actualiza los realm.json
# 2. Reconstruye la imagen del init-container
# 3. Hace push al registry
# 4. Actualiza el values.yaml con la nueva imagen
#
# Uso: ./update-and-deploy-realm.sh <nuevo_dominio> <registry> [tag]
# Ejemplo: ./update-and-deploy-realm.sh 51.68.114.44.nip.io myregistry.io/catena-x v1.0.1

set -e

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Error: Faltan parámetros requeridos"
    echo "Uso: $0 <nuevo_dominio> <registry> [tag]"
    echo ""
    echo "Parámetros:"
    echo "  nuevo_dominio: Dominio a usar (ej: 51.68.114.44.nip.io)"
    echo "  registry: Registry de Docker (ej: myregistry.io/catena-x)"
    echo "  tag: Tag de la imagen (opcional, default: <timestamp>)"
    echo ""
    echo "Ejemplo:"
    echo "  $0 51.68.114.44.nip.io myregistry.io/catena-x"
    echo "  $0 51.68.114.44.nip.io myregistry.io/catena-x v1.0.1"
    exit 1
fi

NEW_DOMAIN="$1"
REGISTRY="$2"
TAG="${3:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_NAME="${REGISTRY}/init-container"
FULL_IMAGE="${IMAGE_NAME}:${TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_CONTAINER_DIR="${SCRIPT_DIR}"
VALUES_FILE="${SCRIPT_DIR}/../charts/umbrella/values-ovh-hosts-portal.yaml"

echo "=========================================="
echo "Despliegue Automático - Realm URLs"
echo "=========================================="
echo "Dominio: ${NEW_DOMAIN}"
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo "Imagen completa: ${FULL_IMAGE}"
echo ""

# Paso 1: Actualizar realm.json
echo "🔹 PASO 1: Actualizando realm.json"
echo "=========================================="
"${SCRIPT_DIR}/update-realm-urls.sh" "${NEW_DOMAIN}"

# Paso 2: Construir imagen
echo ""
echo "🔹 PASO 2: Construyendo imagen Docker"
echo "=========================================="
cd "${INIT_CONTAINER_DIR}"
docker build -t "${FULL_IMAGE}" .

if [ $? -ne 0 ]; then
    echo "❌ Error al construir la imagen"
    exit 1
fi
echo "✅ Imagen construida: ${FULL_IMAGE}"

# Paso 3: Push al registry
echo ""
echo "🔹 PASO 3: Subiendo imagen al registry"
echo "=========================================="
docker push "${FULL_IMAGE}"

if [ $? -ne 0 ]; then
    echo "❌ Error al subir la imagen al registry"
    exit 1
fi
echo "✅ Imagen subida al registry"

# Paso 4: Actualizar values.yaml (opcional, comentado por defecto)
echo ""
echo "🔹 PASO 4: Actualizar values.yaml"
echo "=========================================="
echo "⚠️  MANUAL: Actualiza manualmente el values.yaml con:"
echo ""
echo "centralidp:"
echo "  initContainer:"
echo "    image:"
echo "      repository: ${IMAGE_NAME}"
echo "      tag: ${TAG}"
echo ""
echo "sharedidp:"
echo "  initContainer:"
echo "    image:"
echo "      repository: ${IMAGE_NAME}"
echo "      tag: ${TAG}"
echo ""

# Paso 5: Instrucciones para helm upgrade
echo ""
echo "🔹 PASO 5: Helm Upgrade"
echo "=========================================="
echo "Ejecuta el siguiente comando para actualizar el despliegue:"
echo ""
echo "cd ${SCRIPT_DIR}/../charts/umbrella"
echo "helm upgrade portal . -n portal \\"
echo "  -f values-adopter-portal-for-onboarding.yaml \\"
echo "  -f values-ovh-hosts-portal.yaml \\"
echo "  --set centralidp.initContainer.image.tag=${TAG} \\"
echo "  --set sharedidp.initContainer.image.tag=${TAG}"
echo ""

echo "=========================================="
echo "✅ Proceso completado"
echo "=========================================="
echo ""
echo "IMPORTANTE:"
echo "- Los archivos realm.json han sido actualizados"
echo "- La imagen ${FULL_IMAGE} está lista"
echo "- Ejecuta el helm upgrade según las instrucciones arriba"
echo "- Después del upgrade, NO necesitarás ejecutar fix-keycloak-urls-job"
