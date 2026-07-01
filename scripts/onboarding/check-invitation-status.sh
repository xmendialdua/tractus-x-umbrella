#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: check-invitation-status.sh
# Fecha: 2026-06-30
#
# Problema:
# - Una invitacion puede aparecer en Portal UI como CREATED pero sin correo en
#   smtp4dev porque el proceso de onboarding se queda bloqueado en process_steps.
#
# Solucion:
# - Consultar en una sola ejecucion el estado de proceso, pasos y mailing para
#   identificar rapidamente si el flujo esta bloqueado antes del envio SMTP.
#
# Uso:
#   ./scripts/onboarding/check-invitation-status.sh dataspace@partnera.com
#
# Requisitos:
# - kubeconfig disponible (usa KUBECONFIG actual o kubeconfig.yaml del repo).
# - Acceso al namespace portal.
# -----------------------------------------------------------------------------

set -euo pipefail

EMAIL="${1:-}"
if [[ -z "$EMAIL" ]]; then
  echo "Uso: $0 <email-invitado>"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -z "${KUBECONFIG:-}" && -f "$REPO_ROOT/kubeconfig.yaml" ]]; then
  export KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"
fi

NAMESPACE="portal"
PGPOD="portal-portal-backend-postgresql-0"
DB_USER="portal"
DB_NAME="postgres"

echo "[1/4] Leyendo password de PostgreSQL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NAMESPACE" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/4] Invitacion y aplicacion"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT ci.email, ci.idp_name, ci.application_id, ci.process_id,
       ca.application_status_id, cas.label AS application_status
FROM portal.company_invitations ci
LEFT JOIN portal.company_applications ca ON ca.id = ci.application_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "[3/4] Process steps recientes"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT ps.date_created, pst.label AS step_type, pss.label AS step_status, ps.message
FROM portal.company_invitations ci
JOIN portal.process_steps ps ON ps.process_id = ci.process_id
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE lower(ci.email) = lower('$EMAIL')
ORDER BY ps.date_created DESC
LIMIT 20;
"

echo "[4/4] Estado de mailing"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT ci.email, ci.process_id, mi.id AS mailing_id, mi.mailing_status_id, ms.label AS mailing_status
FROM portal.company_invitations ci
LEFT JOIN portal.mailing_informations mi ON mi.process_id = ci.process_id
LEFT JOIN portal.mailing_statuses ms ON ms.id = mi.mailing_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "Script finalizado"
