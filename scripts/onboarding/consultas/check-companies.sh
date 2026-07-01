#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: check-companies.sh 
# Fecha: 2026-06-30
#
# Descripcion:
# - Este script muestra todas las companias registradas en el portal, junto con su información.
#   Permite consultar si una compania tiene un BPN asignado y otros detalles relevantes.
#
# Uso:
#   ./scripts/onboarding/check-companies.sh
#
# Requisitos:
# - kubeconfig disponible (usa KUBECONFIG actual o kubeconfig.yaml del repo).
# - Acceso al namespace portal.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "${KUBECONFIG:-}" && -f "$REPO_ROOT/kubeconfig.yaml" ]]; then
  export KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"
fi

NAMESPACE="portal"
PGPOD="portal-portal-backend-postgresql-0"
DB_USER="portal"
DB_NAME="postgres"

echo "[1/2] Leyendo password de PostgreSQL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NAMESPACE" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/2] Invitacion y aplicacion"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT * FROM portal.companies ;
"

echo "Script finalizado"
