#!/usr/bin/env bash

set -euo pipefail

# Fix or create connector_url for a partner in portal.connectors using BPN.
#
# Usage:
#   scripts/partner/register-partner-connector-in-db.sh <BPN> <DSP_URL> [options]
#
# Examples:
#   scripts/partner/register-partner-connector-in-db.sh BPNL00000003PRTA https://edc-prta-control.example.com/api/v1/dsp --dry-run
#   scripts/partner/register-partner-connector-in-db.sh BPNL00000003PRTA https://edc-prta-control.example.com/api/v1/dsp --apply
#
# Options:
#   --apply                Execute INSERT/UPDATE (default is dry-run)
#   --dry-run              Print actions and SQL checks only (default)
#   --name <name>          Connector name for INSERT (default: derived from BPN)
#   --status-id <id>       status_id for INSERT (default: 2)
#   --type-id <id>         type_id for INSERT (default: 1)
#   --location-id <CC>     location_id for INSERT (default: DE)
#   -h, --help             Show help
#
# Optional env vars for local DB mode:
#   PORTAL_DB_HOST (default: localhost)
#   PORTAL_DB_PORT (default: 5433)
#   PORTAL_DB_NAME (default: postgres)
#   PORTAL_DB_USER (default: portal)
#   PORTAL_DB_PASSWORD (default: dbpasswordportal)

usage() {
  sed -n '1,40p' "$0" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BPN="${1:-}"
DSP_URL="${2:-}"

if [[ -z "$BPN" || -z "$DSP_URL" ]]; then
  echo "Error: faltan argumentos obligatorios."
  echo
  usage
  exit 1
fi

if [[ ! "$BPN" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Error: BPN inválido: $BPN"
  exit 1
fi

if [[ ! "$DSP_URL" =~ ^https?://.+/api/v1/dsp$ ]]; then
  echo "Error: DSP_URL inválida. Debe terminar en /api/v1/dsp"
  echo "URL recibida: $DSP_URL"
  exit 1
fi

APPLY=0
STATUS_ID=2
TYPE_ID=1
LOCATION_ID="DE"
CONNECTOR_NAME="$(echo "$BPN" | tr '[:upper:]' '[:lower:]')-edc"

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      APPLY=1
      shift
      ;;
    --dry-run)
      APPLY=0
      shift
      ;;
    --name)
      CONNECTOR_NAME="${2:-}"
      shift 2
      ;;
    --status-id)
      STATUS_ID="${2:-}"
      shift 2
      ;;
    --type-id)
      TYPE_ID="${2:-}"
      shift 2
      ;;
    --location-id)
      LOCATION_ID="${2:-}"
      shift 2
      ;;
    *)
      echo "Error: opción desconocida: $1"
      exit 1
      ;;
  esac
done

if [[ ! "$STATUS_ID" =~ ^[0-9]+$ || ! "$TYPE_ID" =~ ^[0-9]+$ ]]; then
  echo "Error: --status-id y --type-id deben ser numéricos"
  exit 1
fi

if [[ ! "$LOCATION_ID" =~ ^[A-Z]{2}$ ]]; then
  echo "Error: --location-id debe ser código país de 2 letras mayúsculas (ej: DE, ES)"
  exit 1
fi

if [[ -z "$CONNECTOR_NAME" ]]; then
  echo "Error: --name no puede estar vacío"
  exit 1
fi

DB_HOST="${PORTAL_DB_HOST:-localhost}"
DB_PORT="${PORTAL_DB_PORT:-5433}"
DB_NAME="${PORTAL_DB_NAME:-postgres}"
DB_USER="${PORTAL_DB_USER:-portal}"
DB_PASSWORD="${PORTAL_DB_PASSWORD:-dbpasswordportal}"

run_psql_local() {
  local flags="$1"
  local sql="$2"
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 $flags <<SQL
$sql
SQL
}

run_psql_k8s() {
  local flags="$1"
  local sql="$2"
  local pod
  pod="$(kubectl get pods -n portal -o name 2>/dev/null | sed 's#^pod/##' | awk '/^portal-portal-backend-postgresql-0$/ {print; exit}')"
  if [[ -z "$pod" ]]; then
    pod="$(kubectl get pods -n portal -o name 2>/dev/null | sed 's#^pod/##' | awk '/^portal-portal-backend-postgresql/ {print; exit}')"
  fi

  if [[ -z "$pod" ]]; then
    echo "Error: No se encontró pod PostgreSQL del portal en namespace 'portal'."
    return 1
  fi

  printf "%s\n" "$sql" | kubectl exec -i -n portal "$pod" -- sh -lc \
    "PSQL_BIN=\"\$(command -v psql 2>/dev/null || true)\"; \
     if [ -z \"\$PSQL_BIN\" ] && [ -x /opt/bitnami/postgresql/bin/psql ]; then PSQL_BIN=/opt/bitnami/postgresql/bin/psql; fi; \
     if [ -z \"\$PSQL_BIN\" ]; then echo 'Error: psql no encontrado en el pod PostgreSQL'; exit 127; fi; \
     PGPASSWORD='${DB_PASSWORD}' \"\$PSQL_BIN\" -U '${DB_USER}' -d '${DB_NAME}' -v ON_ERROR_STOP=1 $flags"
}

MODE=""
if command -v psql >/dev/null 2>&1; then
  if run_psql_local "-At" "SELECT 1;" >/dev/null 2>&1; then
    MODE="local"
  fi
fi
if [[ -z "$MODE" ]]; then
  if command -v kubectl >/dev/null 2>&1; then
    MODE="k8s"
  else
    echo "Error: no hay conexión local a PostgreSQL y tampoco está disponible kubectl."
    exit 1
  fi
fi

psql_run() {
  local flags="$1"
  local sql="$2"
  if [[ "$MODE" == "local" ]]; then
    run_psql_local "$flags" "$sql"
  else
    run_psql_k8s "$flags" "$sql"
  fi
}

echo "=============================================="
echo "Fix Partner Connector"
echo "=============================================="
echo "BPN: $BPN"
echo "DSP_URL: $DSP_URL"
echo "Connector name: $CONNECTOR_NAME"
echo "Mode: $MODE"
if [[ "$APPLY" == "1" ]]; then
  echo "Execution: APPLY"
else
  echo "Execution: DRY-RUN"
fi
echo

SQL_COMPANY="
SELECT id, name, business_partner_number
FROM portal.companies
WHERE business_partner_number = '${BPN}';
"

COMPANY_RAW="$(psql_run "-At -P pager=off" "$SQL_COMPANY")"
if [[ -z "$COMPANY_RAW" ]]; then
  echo "❌ No existe company para BPN: $BPN"
  exit 2
fi

COMPANY_ID="$(echo "$COMPANY_RAW" | head -n1 | cut -d'|' -f1)"
COMPANY_NAME="$(echo "$COMPANY_RAW" | head -n1 | cut -d'|' -f2)"

echo "✅ Company encontrada"
echo "   id: $COMPANY_ID"
echo "   name: $COMPANY_NAME"
echo

SQL_EXISTING="
SELECT id, name, connector_url, status_id, type_id, location_id
FROM portal.connectors
WHERE provider_id = '${COMPANY_ID}'
ORDER BY name;
"

EXISTING="$(psql_run "-At -P pager=off" "$SQL_EXISTING")"
if [[ -n "$EXISTING" ]]; then
  echo "ℹ️ Connectors existentes para este partner:"
  while IFS='|' read -r cid cname curl cstatus ctype cloc; do
    echo "   - id=$cid name=$cname url=$curl status=$cstatus type=$ctype loc=$cloc"
  done <<< "$EXISTING"
else
  echo "ℹ️ No hay connectors para este partner"
fi
echo

if [[ -n "$EXISTING" ]]; then
  TARGET_ID="$(echo "$EXISTING" | head -n1 | cut -d'|' -f1)"
  SQL_MUTATION="
UPDATE portal.connectors
SET
  connector_url = '${DSP_URL}',
  name = '${CONNECTOR_NAME}',
  status_id = ${STATUS_ID},
  type_id = ${TYPE_ID},
  location_id = '${LOCATION_ID}'
WHERE id = '${TARGET_ID}';
"
  ACTION_DESC="UPDATE connector existente id=${TARGET_ID}"
else
  SQL_MUTATION="
INSERT INTO portal.connectors (
  id,
  name,
  connector_url,
  type_id,
  status_id,
  provider_id,
  host_id,
  location_id,
  self_description_document_id
)
VALUES (
  gen_random_uuid(),
  '${CONNECTOR_NAME}',
  '${DSP_URL}',
  ${TYPE_ID},
  ${STATUS_ID},
  '${COMPANY_ID}',
  '${COMPANY_ID}',
  '${LOCATION_ID}',
  NULL
);
"
  ACTION_DESC="INSERT nuevo connector para provider_id=${COMPANY_ID}"
fi

echo "Acción preparada: $ACTION_DESC"
echo

if [[ "$APPLY" == "0" ]]; then
  echo "DRY-RUN: no se aplicaron cambios."
  echo "SQL a ejecutar:"
  echo "----------------------------------------------"
  echo "$SQL_MUTATION"
  echo "----------------------------------------------"
  exit 0
fi

psql_run "" "$SQL_MUTATION"

echo "✅ Cambio aplicado"
echo

echo "Verificación post-cambio:"
SQL_VERIFY="
SELECT con.id, con.name, con.connector_url, con.status_id, con.type_id, con.location_id,
       c.business_partner_number AS bpn
FROM portal.connectors con
JOIN portal.companies c ON c.id = con.provider_id
WHERE c.business_partner_number = '${BPN}'
ORDER BY con.name;
"
psql_run "-P pager=off -x" "$SQL_VERIFY"

echo "\nSugerencia:"
echo "- Revisa GET /api/partners/<email>/details para confirmar management_url"
echo "- Refresca la página /partner-data"