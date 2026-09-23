#!/bin/bash
###############################################################
# Script de Despliegue del Conector EDC de PartnerA
# BPN: BPNL00000003PRTA
# Namespace: umbrella
# Fecha: 2026-07-02
###############################################################

set -e  # Salir si hay algún error

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

NAMESPACE="umbrella"

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Despliegue EDC PartnerA${NC}"
echo -e "${GREEN}============================================${NC}"

# Configurar kubeconfig
export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

# Añadir repositorio Helm si no existe
echo -e "\n${YELLOW}[1/4] Añadiendo repositorio Helm...${NC}"
helm repo add tractusx-dev https://eclipse-tractusx.github.io/charts/dev
helm repo update

# Crear namespace
echo -e "\n${YELLOW}[2/4] Creando namespace ${NAMESPACE}...${NC}"
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Etiquetar el namespace (útil para NetworkPolicies)
kubectl label namespace ${NAMESPACE} name=prta-connector --overwrite

# Desplegar EDC PartnerA
echo -e "\n${YELLOW}[3/4] Desplegando EDC para PartnerA...${NC}"
helm upgrade --install prta-edc ./charts/dataspace-connector-bundle \
  --namespace ${NAMESPACE} \
  --values ./charts/dataspace-connector-bundle/values-prta-connector.yaml \
  --timeout 15m \
  --wait

# Verificar despliegue
echo -e "\n${YELLOW}[4/4] Verificando despliegue...${NC}"
echo -e "\n${GREEN}=== Pods ===${NC}"
kubectl get pods -n ${NAMESPACE}

echo -e "\n${GREEN}=== Servicios ===${NC}"
kubectl get svc -n ${NAMESPACE}

echo -e "\n${GREEN}=== Ingress ===${NC}"
kubectl get ingress -n ${NAMESPACE}

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}✅ Despliegue completado${NC}"
echo -e "${GREEN}============================================${NC}"

echo -e "\n${YELLOW}URLs de acceso (HTTPS habilitado):${NC}"
echo -e "Control Plane: https://edc-prta-control.51.178.94.25.nip.io"
echo -e "Data Plane:    https://edc-prta-data.51.178.94.25.nip.io"

echo -e "\n${YELLOW}Health Check:${NC}"
echo -e "curl -k https://edc-prta-control.51.178.94.25.nip.io/api/check/health"
echo -e "(Usar -k para certificados self-signed)"

echo -e "\n${YELLOW}Ver logs:${NC}"
echo -e "kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/component=controlplane -f"

echo -e "\n${YELLOW}Para eliminar:${NC}"
echo -e "helm uninstall prta-edc -n ${NAMESPACE}"
echo -e "kubectl delete namespace ${NAMESPACE}"
