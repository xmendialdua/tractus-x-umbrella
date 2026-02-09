#!/bin/bash

###############################################################
# Script: Seeding de Business Partners para conectores EDC
#
# Ejecuta Jobs de Kubernetes que registran automáticamente
# las relaciones bidireccionales entre MASS e IKLN.
#
# Uso:
#   ./seed-business-partners.sh
###############################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="${SCRIPT_DIR}/kubeconfig.yaml"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "Business Partner Seeding"
echo "========================================"
echo ""

# Verificar kubeconfig
if [ ! -f "$KUBECONFIG_FILE" ]; then
    echo -e "${RED}Error: kubeconfig.yaml no encontrado${NC}"
    exit 1
fi

export KUBECONFIG="$KUBECONFIG_FILE"

# Función para verificar si un namespace existe
check_namespace() {
    local ns=$1
    if ! kubectl get namespace "$ns" &>/dev/null; then
        echo -e "${RED}Error: Namespace $ns no existe${NC}"
        return 1
    fi
    return 0
}

# Función para eliminar job anterior si existe
cleanup_previous_job() {
    local job_name=$1
    local namespace=$2
    
    if kubectl get job "$job_name" -n "$namespace" &>/dev/null; then
        echo "  Eliminando job anterior..."
        kubectl delete job "$job_name" -n "$namespace" --ignore-not-found=true
        sleep 2
    fi
}

# Función para esperar a que un job complete
wait_for_job() {
    local job_name=$1
    local namespace=$2
    local timeout=300  # 5 minutos
    local elapsed=0
    
    echo "  Esperando a que el job complete..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || echo "")
        local failed=$(kubectl get job "$job_name" -n "$namespace" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || echo "")
        
        if [ "$status" = "True" ]; then
            echo -e "${GREEN}✓ Job completado exitosamente${NC}"
            return 0
        fi
        
        if [ "$failed" = "True" ]; then
            echo -e "${RED}✗ Job falló${NC}"
            echo ""
            echo "Logs del job:"
            kubectl logs job/"$job_name" -n "$namespace" --tail=50
            return 1
        fi
        
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo -e "${RED}✗ Timeout esperando al job${NC}"
    return 1
}

# Seeding para MASS
echo -e "${YELLOW}[1/2] Seeding MASS EDC${NC}"
if check_namespace "mass-connector"; then
    cleanup_previous_job "mass-edc-business-partner-seeding" "mass-connector"
    
    kubectl apply -f "${SCRIPT_DIR}/charts/mass-connector-seeding.yaml"
    
    if wait_for_job "mass-edc-business-partner-seeding" "mass-connector"; then
        echo "  Mostrando logs:"
        kubectl logs job/mass-edc-business-partner-seeding -n mass-connector --tail=20
    else
        echo -e "${RED}  Error en seeding de MASS${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  Namespace mass-connector no encontrado, saltando...${NC}"
fi

echo ""

# Seeding para IKLN
echo -e "${YELLOW}[2/2] Seeding IKLN EDC${NC}"
if check_namespace "ikln-connector"; then
    cleanup_previous_job "ikln-edc-business-partner-seeding" "ikln-connector"
    
    kubectl apply -f "${SCRIPT_DIR}/charts/ikln-connector-seeding.yaml"
    
    if wait_for_job "ikln-edc-business-partner-seeding" "ikln-connector"; then
        echo "  Mostrando logs:"
        kubectl logs job/ikln-edc-business-partner-seeding -n ikln-connector --tail=20
    else
        echo -e "${RED}  Error en seeding de IKLN${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}  Namespace ikln-connector no encontrado, saltando...${NC}"
fi

echo ""
echo "========================================"
echo -e "${GREEN}Seeding completado${NC}"
echo "========================================"
echo ""
echo "Relaciones configuradas:"
echo "  • MASS confía en: IKLN (BPNL00000002IKLN)"
echo "  • IKLN confía en: MASS (BPNL00000000MASS)"
echo ""
echo "Los conectores ahora pueden negociar contratos entre sí."
