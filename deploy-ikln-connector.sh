#!/bin/bash
###############################################################
# Script de Despliegue del Conector EDC de Ikerlan
# BPN: BPNL00000002IKLN
# Namespace: ikln-connector
# Fecha: 2026-02-05
###############################################################

set -e  # Salir si hay algún error

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Despliegue EDC Ikerlan${NC}"
echo -e "${GREEN}============================================${NC}"

# Configurar kubeconfig
export KUBECONFIG=/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml

# Añadir repositorio Helm si no existe
echo -e "\n${YELLOW}[1/4] Añadiendo repositorio Helm...${NC}"
helm repo add tractusx-dev https://eclipse-tractusx.github.io/charts/dev
helm repo update

# Crear namespace para Ikerlan
echo -e "\n${YELLOW}[2/4] Creando namespace ikln-connector...${NC}"
kubectl create namespace ikln-connector --dry-run=client -o yaml | kubectl apply -f -

# Etiquetar el namespace (útil para NetworkPolicies)
kubectl label namespace ikln-connector name=ikln-connector --overwrite

# Desplegar EDC Ikerlan
echo -e "\n${YELLOW}[3/4] Desplegando EDC para Ikerlan...${NC}"
helm upgrade --install ikln-edc tractusx-dev/dataspace-connector-bundle \
  --namespace ikln-connector \
  --values /home/xmendialdua/projects/assembly/tractus-x-umbrella/charts/values-ikln-connector.yaml \
  --timeout 15m \
  --wait

# Verificar despliegue
echo -e "\n${YELLOW}[4/4] Verificando despliegue...${NC}"
echo -e "\n${GREEN}=== Pods ===${NC}"
kubectl get pods -n ikln-connector

echo -e "\n${GREEN}=== Servicios ===${NC}"
kubectl get svc -n ikln-connector

echo -e "\n${GREEN}=== Ingress ===${NC}"
kubectl get ingress -n ikln-connector

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}✅ Despliegue completado${NC}"
echo -e "${GREEN}============================================${NC}"

echo -e "\n${YELLOW}URLs de acceso:${NC}"
echo -e "Control Plane: http://edc-ikln-control.51.178.94.25.nip.io"
echo -e "Data Plane:    http://edc-ikln-data.51.178.94.25.nip.io"

echo -e "\n${YELLOW}Health Check:${NC}"
echo -e "curl http://edc-ikln-control.51.178.94.25.nip.io/api/check/health"

echo -e "\n${YELLOW}Ver logs:${NC}"
echo -e "kubectl logs -n ikln-connector -l app.kubernetes.io/component=controlplane -f"

echo -e "\n${YELLOW}Para eliminar:${NC}"
echo -e "helm uninstall ikln-edc -n ikln-connector"
echo -e "kubectl delete namespace ikln-connector"
