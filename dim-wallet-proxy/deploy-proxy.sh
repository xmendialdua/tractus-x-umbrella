#!/bin/bash

###############################################################
# Script de despliegue del DIM Wallet Proxy
# Fecha: 9 de febrero de 2026
###############################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="${SCRIPT_DIR}/../kubeconfig.yaml"
IMAGE_NAME="dim-wallet-proxy:latest"

echo "============================================"
echo "Despliegue DIM Wallet Proxy"
echo "============================================"
echo ""

# [1/4] Construir imagen Docker
echo "[1/4] Construyendo imagen Docker..."
cd "${SCRIPT_DIR}"
docker build -t "${IMAGE_NAME}" . || {
    echo "❌ Error construyendo imagen Docker"
    exit 1
}
echo "✅ Imagen construida"
echo ""

# [2/4] Cargar imagen en el cluster
echo "[2/4] Cargando imagen en el cluster..."
# Detectar si es kind o minikube
if kubectl --kubeconfig="${KUBECONFIG_PATH}" get nodes -o jsonpath='{.items[0].metadata.labels}' | grep -q "kind"; then
    echo "Detectado cluster kind"
    kind load docker-image "${IMAGE_NAME}" || echo "⚠️  No se pudo cargar en kind, continuando..."
elif command -v minikube &> /dev/null; then
    echo "Detectado minikube"
    minikube image load "${IMAGE_NAME}" || echo "⚠️  No se pudo cargar en minikube, continuando..."
else
    echo "⚠️  Cluster remoto detectado - asegúrate de que la imagen esté en un registry accesible"
fi
echo ""

# [3/4] Aplicar manifiestos
echo "[3/4] Desplegando en Kubernetes..."
kubectl --kubeconfig="${KUBECONFIG_PATH}" apply -f "${SCRIPT_DIR}/deployment.yaml"
echo ""

# [4/4] Esperar a que el pod esté listo
echo "[4/4] Esperando a que el proxy esté listo..."
kubectl --kubeconfig="${KUBECONFIG_PATH}" wait --for=condition=ready pod -l app=dim-wallet-proxy -n portal --timeout=120s || {
    echo "❌ Error esperando a que el pod esté listo"
    echo ""
    echo "Estado de los pods:"
    kubectl --kubeconfig="${KUBECONFIG_PATH}" get pods -n portal -l app=dim-wallet-proxy
    echo ""
    echo "Logs:"
    kubectl --kubeconfig="${KUBECONFIG_PATH}" logs -n portal -l app=dim-wallet-proxy --tail=50
    exit 1
}
echo ""

# Verificación
echo "============================================"
echo "✅ Despliegue completado"
echo "============================================"
echo ""
echo "=== Pods ==="
kubectl --kubeconfig="${KUBECONFIG_PATH}" get pods -n portal -l app=dim-wallet-proxy
echo ""
echo "=== Service ==="
kubectl --kubeconfig="${KUBECONFIG_PATH}" get svc -n portal dim-wallet-proxy
echo ""
echo "============================================"
echo "Proxy disponible en:"
echo "  Internal: http://dim-wallet-proxy.portal.svc.cluster.local:8080"
echo ""
echo "Ver logs:"
echo "  kubectl --kubeconfig=${KUBECONFIG_PATH} logs -n portal -l app=dim-wallet-proxy -f"
echo ""
echo "Siguiente paso: Actualizar configuración de conectores"
echo "  Modificar values-ikln-connector.yaml y values-mass-connector.yaml"
echo "  para usar: http://dim-wallet-proxy.portal.svc.cluster.local:8080"
echo "============================================"
