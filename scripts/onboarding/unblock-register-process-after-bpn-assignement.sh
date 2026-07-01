#!/usr/bin/env bash


# Desbloquea el proceso de registro de un partner después de asignar su BPN
# manualmente en la base de datos,
# cuando el proceso automático ha fallado en CREATE_BUSINESS_PARTNER_NUMBER_PUSH.
#
# Pasos que realiza:
# 1. Marca RETRIGGER_ASSIGN_BPN_TO_USERS como DONE
# 2. Crea un Job manual del processes-worker para forzar procesamiento
# 3. Espera a que el Job complete
# 4. Verifica el estado final del proceso de registro
#
## Prerequisitos:
# - El BPN debe estar ya asignado en portal.companies
#   Para eso deberemos ejecutar el script
#      assign-bpn-to-company.sh para poner business_partner_number. 
#
#
# Uso:
#   ./scripts/onboarding/unblock-register-process-after-bpn-assignement.sh <COMPANY_NAME>
#
# Ejemplo:
#   ./scripts/onboarding/unblock-register-process-after-bpn-assignement.sh PartnerA


set -euo pipefail

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"

COMPANY_NAME="${1:-}"
STOP_AFTER_STEP="${STOP_AFTER_STEP:-0}"

if [[ -z "$COMPANY_NAME" ]]; then
  echo "ERROR: falta COMPANY_NAME"
  echo "Uso: $0 <COMPANY_NAME>"
  echo "Ejemplo: $0 PartnerA"
  echo "Opcional: STOP_AFTER_STEP=1..7 para parar tras un paso"
  echo "Ejemplo: STOP_AFTER_STEP=2 $0 PartnerA"
  exit 1
fi

if ! [[ "$STOP_AFTER_STEP" =~ ^[0-9]+$ ]]; then
  echo "ERROR: STOP_AFTER_STEP debe ser numerico"
  exit 1
fi

if ! kubectl get pod -n "$NAMESPACE" "$POD" >/dev/null 2>&1; then
  echo "ERROR: pod '$POD' no encontrado en namespace '$NAMESPACE'"
  exit 1
fi

# Escape simple de comillas para literales SQL.
SQL_COMPANY_NAME="${COMPANY_NAME//\'/\'\'}"

sql_exec() {
  local query="$1"
  kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" \
    psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDATABASE" -c "$query"
}

sql_raw() {
  local query="$1"
  kubectl exec -n "$NAMESPACE" "$POD" -- env PGPASSWORD="$PGPASSWORD" \
    psql -v ON_ERROR_STOP=1 -U "$PGUSER" -d "$PGDATABASE" -t -A -F '|' -c "$query"
}

stop_if_requested() {
  local current_step="$1"
  if (( STOP_AFTER_STEP == current_step )); then
    echo "STOP_AFTER_STEP=$STOP_AFTER_STEP alcanzado. Saliendo para validacion."
    exit 0
  fi
}

echo "=========================================="
echo "Unblock Register Process After BPN Assignment"
echo "=========================================="
echo "Company: $COMPANY_NAME"
echo "Namespace: $NAMESPACE"
echo ""

echo "[1/7] Buscando aplicacion mas reciente de la compania"
#     Lee application_id, process_id, estado y BPN actual de la compania."
APP_INFO="$(sql_raw "
SELECT
  ca.id,
  ca.checklist_process_id,
  COALESCE(c.business_partner_number, ''),
  COALESCE(ca.application_status_id::text, ''),
  COALESCE(cs.label, ''),
  COALESCE(ci.email, ''),
  COALESCE(to_char(ca.date_created AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'), '')
FROM portal.companies c
JOIN portal.company_applications ca ON ca.company_id = c.id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_invitations ci ON ci.application_id = ca.id
WHERE c.name = '$SQL_COMPANY_NAME'
ORDER BY ca.date_created DESC
LIMIT 1;")"

if [[ -z "$APP_INFO" ]]; then
  echo "ERROR: no se encontro aplicacion para la compania '$COMPANY_NAME'"
  exit 1
fi

APPLICATION_ID="$(echo "$APP_INFO" | cut -d'|' -f1)"
PROCESS_ID="$(echo "$APP_INFO" | cut -d'|' -f2)"
BPN_VALUE="$(echo "$APP_INFO" | cut -d'|' -f3)"
APP_STATUS_ID="$(echo "$APP_INFO" | cut -d'|' -f4)"
COMPANY_STATUS="$(echo "$APP_INFO" | cut -d'|' -f5)"
INVITATION_EMAIL="$(echo "$APP_INFO" | cut -d'|' -f6)"
APP_DATE="$(echo "$APP_INFO" | cut -d'|' -f7)"

if [[ -z "$PROCESS_ID" ]]; then
  echo "ERROR: la aplicacion no tiene checklist_process_id"
  echo "application_id=$APPLICATION_ID"
  exit 1
fi

if [[ -z "$BPN_VALUE" ]]; then
  echo "ERROR: la compania aun no tiene BPN asignado"
  echo "Ejecuta primero: ./scripts/onboarding/assign-bpn-to-company.sh <BPN_VALUE> \"$COMPANY_NAME\""
  exit 1
fi

echo "application_id: $APPLICATION_ID"
echo "process_id: $PROCESS_ID"
echo "email: ${INVITATION_EMAIL:-no-disponible}"
echo "application_date: ${APP_DATE:-no-disponible}"
echo "company_status: ${COMPANY_STATUS:-no-disponible}"
echo "application_status_id: ${APP_STATUS_ID:-no-disponible}"
echo "bpn: $BPN_VALUE"
echo ""
stop_if_requested 1

echo "[2/7] Estado actual de steps clave"
#     Muestra los steps de BPN/activacion para saber el punto exacto del bloqueo."
sql_exec "
SELECT
  ps.date_created,
  pst.label AS step_type,
  pss.label AS step_status,
  ps.id AS step_id,
  ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE ps.process_id = '$PROCESS_ID'
  AND pst.label IN (
    'CREATE_BUSINESS_PARTNER_NUMBER_PUSH',
    'ASSIGN_BPN_TO_USERS',
    'RETRIGGER_ASSIGN_BPN_TO_USERS',
    'FINISH_APPLICATION_ACTIVATION'
  )
ORDER BY ps.date_created;
"
stop_if_requested 2

echo "[3/7] Marcando RETRIGGER_ASSIGN_BPN_TO_USERS como DONE (si existe)"
#    Fuerza el step de reintento de asignacion de BPN a estado DONE."
UPDATE_RESULT="$(sql_exec "
UPDATE portal.process_steps ps
SET process_step_status_id = (
    SELECT id FROM portal.process_step_statuses WHERE label = 'DONE' LIMIT 1
  ),
  date_last_changed = NOW()
WHERE ps.id = (
  SELECT ps2.id
  FROM portal.process_steps ps2
  JOIN portal.process_step_types pst2 ON pst2.id = ps2.process_step_type_id
  WHERE ps2.process_id = '$PROCESS_ID'
    AND pst2.label = 'RETRIGGER_ASSIGN_BPN_TO_USERS'
  ORDER BY ps2.date_created DESC
  LIMIT 1
)
RETURNING ps.id;
")"

echo "$UPDATE_RESULT"
stop_if_requested 3

echo "[4/7] Insertando FINISH_APPLICATION_ACTIVATION (TODO) si no existe"
echo "      Inserta el step final de activacion para que el worker pueda continuar."
INSERT_RESULT="$(sql_exec "
INSERT INTO portal.process_steps (
  id,
  process_step_type_id,
  process_step_status_id,
  date_created,
  date_last_changed,
  process_id,
  message
)
SELECT
  gen_random_uuid(),
  (SELECT id FROM portal.process_step_types WHERE label = 'FINISH_APPLICATION_ACTIVATION' LIMIT 1),
  (SELECT id FROM portal.process_step_statuses WHERE label = 'TODO' LIMIT 1),
  NOW(),
  NOW(),
  '$PROCESS_ID',
  'Inserted by unblock-short.sh after manual BPN assignment'
WHERE NOT EXISTS (
  SELECT 1
  FROM portal.process_steps x
  JOIN portal.process_step_types t ON t.id = x.process_step_type_id
  WHERE x.process_id = '$PROCESS_ID'
    AND t.label = 'FINISH_APPLICATION_ACTIVATION'
);
")"

echo "$INSERT_RESULT"
echo ""
stop_if_requested 4

echo "[5/7] Creando Job manual de processes-worker"
echo "      Lanza una ejecucion manual del worker para procesar steps pendientes."
JOB_NAME="portal-processes-worker-manual-$(date +%s)"
kubectl create job "$JOB_NAME" --from=cronjob/portal-processes-worker -n "$NAMESPACE"
echo "job_name: $JOB_NAME"
echo ""
stop_if_requested 5

echo "[6/7] Esperando finalizacion del Job (timeout 180s)"
echo "      Espera a que el job termine y corta en caso de fallo."
TIMEOUT=180
ELAPSED=0
while [[ $ELAPSED -lt $TIMEOUT ]]; do
  JOB_STATUS="$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null || true)"
  if [[ "$JOB_STATUS" == "True" ]]; then
    echo "Job completado"
    break
  fi

  JOB_FAILED="$(kubectl get job "$JOB_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null || true)"
  if [[ "$JOB_FAILED" == "True" ]]; then
    echo "ERROR: Job fallo"
    echo "Logs: kubectl logs -n $NAMESPACE job/$JOB_NAME"
    exit 1
  fi

  sleep 5
  ELAPSED=$((ELAPSED + 5))
  echo -n "."
done

echo
echo

if [[ $ELAPSED -ge $TIMEOUT ]]; then
  echo "AVISO: timeout esperando el Job"
  echo "Estado: kubectl get job $JOB_NAME -n $NAMESPACE"
  echo "Logs: kubectl logs -n $NAMESPACE job/$JOB_NAME"
  echo ""
fi
stop_if_requested 6

echo "[7/7] Estado final (ultimos 10 steps)"
echo "      Verifica los ultimos steps y el estado final de aplicacion/compania."
sql_exec "
SELECT
  ps.date_created,
  pst.label AS step_type,
  pss.label AS step_status,
  ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id = ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id = ps.process_step_status_id
WHERE ps.process_id = '$PROCESS_ID'
ORDER BY ps.date_created DESC
LIMIT 10;
"

echo "Resumen final de aplicacion/compania"
sql_exec "
SELECT
  c.name AS company_name,
  c.business_partner_number AS bpn,
  cs.label AS company_status,
  cas.label AS application_status
FROM portal.company_applications ca
JOIN portal.companies c ON c.id = ca.company_id
LEFT JOIN portal.company_statuses cs ON cs.id = c.company_status_id
LEFT JOIN portal.company_application_statuses cas ON cas.id = ca.application_status_id
WHERE ca.id = '$APPLICATION_ID';
"
stop_if_requested 7

echo "Proceso completado"
