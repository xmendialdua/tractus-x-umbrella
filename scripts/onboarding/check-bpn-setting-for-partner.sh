#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: check-bnp-setting-for-partner.sh
# Fecha: 2026-07-01
#
# Problema:
# - Un partner puede quedarse sin BPN aunque la invitacion y el usuario se hayan
#   creado correctamente.
#
# Solucion:
# - Reunir en una sola ejecucion evidencias de base de datos, checklist,
#   process steps, configuracion BPDM y logs de pods para identificar la causa
#   real del fallo de asignacion del BPN.
#
# Uso:
#   ./scripts/onboarding/check-bnp-setting-for-partner.sh dataspace@partnera.com
#
# Requisitos:
# - kubeconfig disponible (usa kubeconfig.yaml del repo si existe).
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
LOG_TAIL="${LOG_TAIL:-200}"
LOG_PODS_PER_PREFIX="${LOG_PODS_PER_PREFIX:-5}"

sql_query() {
  local query="$1"
  kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
    psql -U "$DB_USER" -d "$DB_NAME" -c "$query"
}

sql_query_raw() {
  local query="$1"
  kubectl exec -n "$NAMESPACE" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
    psql -U "$DB_USER" -d "$DB_NAME" -t -A -F '|' -c "$query"
}

latest_pod_by_prefix() {
  local prefix="$1"
  kubectl get pods -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp -o name \
    | rg "^pod/${prefix}" | tail -n 1 | sed 's|^pod/||'
}

recent_pods_by_prefix() {
  local prefix="$1"
  kubectl get pods -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp -o name \
    | rg "^pod/${prefix}" | tail -n "$LOG_PODS_PER_PREFIX" | sed 's|^pod/||'
}

print_logs_for_pod() {
  local pod_name="$1"
  local title="$2"
  local pattern="$3"
  local since_time="$4"

  echo "$title"

  if [[ -z "$pod_name" ]]; then
    echo "No se encontro pod"
    echo ""
    return
  fi

  echo "Pod: $pod_name"
  echo "Filtrado por: $pattern"
  if [[ -n "$since_time" ]]; then
    echo "Desde: $since_time"
  fi

  if kubectl logs -n "$NAMESPACE" "$pod_name" ${since_time:+--since-time="$since_time"} 2>/dev/null \
    | rg -iv 'healthz|ready|readiness|liveness|/actuator' \
    | rg -i "$pattern"; then
    true
  else
    echo "Sin coincidencias directas en los ultimos $LOG_TAIL logs. Ultimas 40 lineas sin filtrar:"
    kubectl logs -n "$NAMESPACE" "$pod_name" ${since_time:+--since-time="$since_time"} --tail=40 2>/dev/null || true
  fi

  echo ""
}

print_logs_for_prefix() {
  local prefix="$1"
  local title="$2"
  local pattern="$3"
  local since_time="$4"
  local any_found="false"

  echo "$title"
  while IFS= read -r pod_name; do
    [[ -z "$pod_name" ]] && continue
    any_found="true"
    print_logs_for_pod "$pod_name" "" "$pattern" "$since_time"
  done < <(recent_pods_by_prefix "$prefix")

  if [[ "$any_found" == "false" ]]; then
    echo "No se encontraron pods con prefijo $prefix"
    echo ""
  fi
}

echo "KUBECONFIG=${KUBECONFIG:-no-definido}"
echo "[1/9] Leyendo password de PostgreSQL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NAMESPACE" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/9] Resumen de invitacion, empresa y aplicacion"
sql_query "
SELECT
  ci.email,
  ci.idp_name,
  ci.application_id,
  ci.process_id AS invitation_process_id,
  c.id AS company_id,
  c.name AS company_name,
  c.business_partner_number AS bpn,
  c.company_status_id,
  cs.label AS company_status,
  ca.id AS application_id_real,
  ca.checklist_process_id,
  ca.application_status_id,
  cas.label AS application_status,
  ca.date_created,
  ca.date_last_changed
FROM portal.company_invitations ci
LEFT JOIN portal.company_applications ca ON ca.id = ci.application_id
LEFT JOIN portal.companies c ON c.id = ca.company_id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

APP_INFO="$(sql_query_raw "
SELECT
  COALESCE(c.id::text, ''),
  COALESCE(c.name, ''),
  COALESCE(ca.id::text, ''),
  COALESCE(ca.checklist_process_id::text, ''),
  COALESCE(ci.process_id::text, ''),
  COALESCE(to_char(ca.date_created AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), '')
FROM portal.company_invitations ci
LEFT JOIN portal.company_applications ca ON ca.id = ci.application_id
LEFT JOIN portal.companies c ON c.id = ca.company_id
WHERE lower(ci.email) = lower('$EMAIL')
LIMIT 1;")"

COMPANY_ID="$(echo "$APP_INFO" | cut -d'|' -f1)"
COMPANY_NAME="$(echo "$APP_INFO" | cut -d'|' -f2)"
APPLICATION_ID="$(echo "$APP_INFO" | cut -d'|' -f3)"
CHECKLIST_PROCESS_ID="$(echo "$APP_INFO" | cut -d'|' -f4)"
INVITATION_PROCESS_ID="$(echo "$APP_INFO" | cut -d'|' -f5)"
APPLICATION_DATE_RFC3339="$(echo "$APP_INFO" | cut -d'|' -f6)"

if [[ -z "$APPLICATION_ID" ]]; then
  echo "No se encontro application_id para $EMAIL"
  exit 1
fi

echo "[3/9] Steps del proceso de invitacion"
sql_query "
SELECT
  ps.date_created,
  pst.label AS step_type,
  pss.label AS step_status,
  ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE ps.process_id = '$INVITATION_PROCESS_ID'
ORDER BY ps.date_created;
"

echo "[4/9] Estado de mailing"
sql_query "
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

echo "[5/9] Checklist de aplicacion con foco en BPN (portal.application_checklist)"
sql_query "
SELECT
  ac.date_created,
  act.label AS checklist_type,
  acs.label AS checklist_status,
  ac.comment
FROM portal.application_checklist ac
JOIN portal.application_checklist_types act ON act.id = ac.application_checklist_entry_type_id
JOIN portal.application_checklist_statuses acs ON acs.id = ac.application_checklist_entry_status_id
WHERE ac.application_id = '$APPLICATION_ID'
ORDER BY ac.date_created;
"

echo "[6/9] Steps del checklist process ligados a la aplicacion (portal.process_steps)"
if [[ -n "$CHECKLIST_PROCESS_ID" ]]; then
  sql_query "
  SELECT
    ps.date_created,
    pst.label AS step_type,
    pss.label AS step_status,
    ps.message
  FROM portal.process_steps ps
  JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
  JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
  WHERE ps.process_id = '$CHECKLIST_PROCESS_ID'
  ORDER BY ps.date_created;
  "
else
  echo "La aplicacion no tiene checklist_process_id informado"
fi

echo "[7/9] Configuracion de BPDM Gate usada por Portal"
kubectl get configmap portal-bpdm-gate -n "$NAMESPACE" -o yaml | rg -n "base-url:|portalGateAddress|orchestrator|pool|gate|business-partners" || true
echo ""
echo "Ingress portal-bpdm-gate"
kubectl get ingress portal-bpdm-gate -n "$NAMESPACE" -o yaml | rg -n "host:|path:|service:|name:|number:" || true
echo ""

echo "[8/9] Logs relevantes de pods"
LOG_PATTERN="${EMAIL}|${APPLICATION_ID}|${CHECKLIST_PROCESS_ID}|${COMPANY_ID}|${COMPANY_NAME}|business-partner|bpdm|404|statuscode"
echo "Fecha base para logs: ${APPLICATION_DATE_RFC3339:-no-disponible}"
echo ""

print_logs_for_prefix 'portal-processes-worker-' 'Logs portal-processes-worker (pods recientes)' "$LOG_PATTERN" "$APPLICATION_DATE_RFC3339"
print_logs_for_prefix 'portal-registration-service-' 'Logs portal-registration-service (pods recientes)' "$LOG_PATTERN" "$APPLICATION_DATE_RFC3339"
print_logs_for_prefix 'portal-bpdm-gate-' 'Logs portal-bpdm-gate (pods recientes)' "$LOG_PATTERN" "$APPLICATION_DATE_RFC3339"

echo "[9/9] Resumen probable de causa"
sql_query "
SELECT
  c.name AS company_name,
  c.business_partner_number AS bpn,
  cs.label AS company_status,
  cas.label AS application_status,
  act.label AS checklist_type,
  acs.label AS checklist_status,
  ac.comment AS checklist_comment
FROM portal.company_invitations ci
JOIN portal.company_applications ca ON ca.id = ci.application_id
JOIN portal.companies c ON c.id = ca.company_id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
LEFT JOIN portal.application_checklist ac ON ac.application_id = ca.id AND ac.application_checklist_entry_type_id = 2
LEFT JOIN portal.application_checklist_types act ON act.id = ac.application_checklist_entry_type_id
LEFT JOIN portal.application_checklist_statuses acs ON acs.id = ac.application_checklist_entry_status_id
WHERE lower(ci.email) = lower('$EMAIL');
"

echo "Diagnostico finalizado"