#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: path1-retry-step405.sh
# Fecha: 2026-06-30
#
# Problema:
# - El proceso de invitacion queda bloqueado en step 405
#   (INVITATION_UPDATE_CENTRAL_IDP_URLS) con estado FAILED.
#
# Solucion (Path 1):
# - Reintentar el step 405 de forma limpia (sin skip de 405).
# - Lanzar portal-processes-worker manual.
# - Verificar si 405 deja de fallar y si se crea mailing.
#
# Uso:
#   ./scripts/onboarding/path1-retry-step405.sh dataspace@partnera.com
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

NS="portal"
PGPOD="portal-portal-backend-postgresql-0"
DBU="portal"
DBN="postgres"

echo "[1/5] Password DB"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NS" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/5] Resolver process_id"
PROCESS_ID="$(kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -t -A -c "
SELECT ci.process_id
FROM portal.company_invitations ci
WHERE lower(ci.email)=lower('$EMAIL')
LIMIT 1;")"

if [[ -z "$PROCESS_ID" ]]; then
  echo "No se encontro process_id para $EMAIL"
  exit 1
fi

echo "process_id=$PROCESS_ID"

echo "[3/5] Reabrir 405 como TODO y limpiar RETRIGGER 415 en TODO"
kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -v ON_ERROR_STOP=1 -c "
BEGIN;

UPDATE portal.process_steps
SET process_step_status_id = 1,
    date_last_changed = NOW(),
    message = NULL
WHERE id = (
  SELECT id FROM portal.process_steps
  WHERE process_id = '$PROCESS_ID' AND process_step_type_id = 405
  ORDER BY date_created DESC
  LIMIT 1
);

UPDATE portal.process_steps
SET process_step_status_id = 3,
    date_last_changed = NOW()
WHERE process_id = '$PROCESS_ID'
  AND process_step_type_id = 415
  AND process_step_status_id = 1;

COMMIT;
"

echo "[4/5] Lanzar worker manual"
JOB="portal-processes-worker-manual-path1-$(date +%s)"
kubectl create job --from=cronjob/portal-processes-worker "$JOB" -n "$NS"
kubectl wait --for=condition=complete --timeout=180s "job/$JOB" -n "$NS" || true

echo "[5/5] Verificar steps y mailing"
kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -c "
SELECT ps.id, pst.label AS step_type, pss.label AS step_status, ps.date_created, ps.date_last_changed, ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id=ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id=ps.process_step_status_id
WHERE ps.process_id='$PROCESS_ID' AND ps.process_step_type_id IN (405,406,415)
ORDER BY ps.date_created DESC;"

kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -c "
SELECT ci.email, ci.process_id, mi.id AS mailing_id, ms.label AS mailing_status
FROM portal.company_invitations ci
LEFT JOIN portal.mailing_informations mi ON mi.process_id=ci.process_id
LEFT JOIN portal.mailing_statuses ms ON ms.id=mi.mailing_status_id
WHERE lower(ci.email)=lower('$EMAIL');"

echo "Retry Path1 completado"
