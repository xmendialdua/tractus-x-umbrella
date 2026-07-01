#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: check-invitation-activation-status.sh
# Fecha: 2026-07-01
#
# Problema:
# - Un partner puede tener la invitacion avanzada pero la activacion de empresa
#   bloqueada en otro proceso distinto, normalmente antes o durante la
#   asignacion del BPN.
#
# Solucion:
# - Consultar en una sola ejecucion el estado de invitacion, mailing,
#   aplicacion, empresa, BPN y steps del proceso de activacion.
#
# Uso:
#   ./scripts/onboarding/check-invitation-activation-status.sh dataspace@partnera.com
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
REPO_KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"

if [[ -f "$REPO_KUBECONFIG" ]]; then
  export KUBECONFIG="$REPO_KUBECONFIG"
fi

NAMESPACE="portal"
PGPOD="portal-portal-backend-postgresql-0"
DB_USER="portal"
DB_NAME="postgres"

echo "KUBECONFIG=${KUBECONFIG:-no-definido}"
echo "[1/6] Leyendo password de PostgreSQL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NAMESPACE" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/6] Resumen de invitacion, aplicacion y empresa"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
  ci.email,
  ci.idp_name,
  ci.application_id,
  ci.process_id AS invitation_process_id,
  ca.id AS activation_process_id,
  c.id AS company_id,
  c.name AS company_name,
  c.business_partner_number AS bpn,
  cs.label AS company_status,
  ca.application_status_id,
  cas.label AS application_status
FROM portal.company_invitations ci
LEFT JOIN portal.company_applications ca ON ca.id = ci.application_id
LEFT JOIN portal.companies c ON c.id = ca.company_id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "[3/6] Steps del proceso de invitacion"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
  ps.date_created,
  pst.label AS step_type,
  pss.label AS step_status,
  ps.message
FROM portal.company_invitations ci
JOIN portal.process_steps ps ON ps.process_id = ci.process_id
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE lower(ci.email) = lower('$EMAIL')
ORDER BY ps.date_created;
"

echo "[4/6] Estado de mailing"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
  ci.email,
  ci.process_id AS invitation_process_id,
  mi.id AS mailing_id,
  mi.mailing_status_id,
  ms.label AS mailing_status
FROM portal.company_invitations ci
LEFT JOIN portal.mailing_informations mi ON mi.process_id = ci.process_id
LEFT JOIN portal.mailing_statuses ms ON ms.id = mi.mailing_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "[5/6] Estado del proceso de activacion (APPLICATION_CHECKLIST)"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
  p.id AS process_id,
  p.process_type_id,
  c.name AS company_name,
  c.business_partner_number AS bpn,
  cs.label AS company_status,
  ca.application_status_id,
  cas.label AS application_status,
  p.lock_expiry_date
FROM portal.company_invitations ci
JOIN portal.company_applications ca ON ca.id = ci.application_id
JOIN portal.processes p ON p.id = ca.id
JOIN portal.companies c ON c.id = ca.company_id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
WHERE lower(ci.email) = lower('$EMAIL')
  AND p.process_type_id = 1;
"

echo "[6/6] Steps del proceso de activacion con foco en BPN"
kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
  ps.date_created,
  pst.label AS step_type,
  pss.label AS step_status,
  ps.message
FROM portal.company_invitations ci
JOIN portal.company_applications ca ON ca.id = ci.application_id
JOIN portal.processes p ON p.id = ca.id
JOIN portal.process_steps ps ON ps.process_id = p.id
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE lower(ci.email) = lower('$EMAIL')
  AND p.process_type_id = 1
ORDER BY ps.date_created;
"

echo "Script finalizado"