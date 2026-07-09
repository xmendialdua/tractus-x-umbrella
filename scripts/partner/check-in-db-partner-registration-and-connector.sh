#!/usr/bin/env bash

set -euo pipefail

# Check partner presence in Portal DB by BPN:
# - portal.companies
# - portal.company_users (via identities -> companies)
# - portal.connectors (connector_url)
#
# Usage:
#   scripts/partner/check-in-db-partner-registration-and-connector.sh BPNL00000003PRTA
#
# Optional env vars for local DB mode:
#   PORTAL_DB_HOST (default: localhost)
#   PORTAL_DB_PORT (default: 5433)
#   PORTAL_DB_NAME (default: postgres)
#   PORTAL_DB_USER (default: portal)
#   PORTAL_DB_PASSWORD (default: dbpasswordportal)

BPN="${1:-}"
if [[ -z "$BPN" ]]; then
  echo "Usage: $0 <BPN>"
  exit 1
fi

if [[ ! "$BPN" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Error: BPN contiene caracteres no permitidos: $BPN"
  exit 1
fi

DB_HOST="${PORTAL_DB_HOST:-localhost}"
DB_PORT="${PORTAL_DB_PORT:-5433}"
DB_NAME="${PORTAL_DB_NAME:-postgres}"
DB_USER="${PORTAL_DB_USER:-portal}"
DB_PASSWORD="${PORTAL_DB_PASSWORD:-dbpasswordportal}"

SQL_COMPANY="
SELECT c.id, c.name, c.business_partner_number, c.company_status_id
FROM portal.companies c
WHERE c.business_partner_number = '${BPN}';
"

SQL_USERS="
SELECT cu.id, cu.email, COALESCE(cu.firstname, '') AS firstname, COALESCE(cu.lastname, '') AS lastname
FROM portal.company_users cu
JOIN portal.identities i ON i.id = cu.id
JOIN portal.companies c ON c.id = i.company_id
WHERE c.business_partner_number = '${BPN}'
ORDER BY cu.email;
"

SQL_CONNECTORS="
SELECT con.id, con.name, con.connector_url, con.status_id, con.type_id, con.provider_id
FROM portal.connectors con
JOIN portal.companies c ON c.id = con.provider_id
WHERE c.business_partner_number = '${BPN}'
ORDER BY con.name;
"

SQL_COUNTS="
WITH target_company AS (
  SELECT id FROM portal.companies WHERE business_partner_number = '${BPN}'
)
SELECT
  (SELECT COUNT(*)::int FROM portal.companies WHERE business_partner_number = '${BPN}') AS company_count,
  (SELECT COUNT(*)::int
   FROM portal.company_users cu
   JOIN portal.identities i ON i.id = cu.id
   JOIN target_company tc ON tc.id = i.company_id) AS users_count,
  (SELECT COUNT(*)::int FROM portal.connectors con JOIN target_company tc ON tc.id = con.provider_id) AS connectors_count,
  (SELECT COUNT(*)::int FROM portal.connectors con JOIN target_company tc ON tc.id = con.provider_id WHERE COALESCE(con.connector_url, '') <> '') AS connectors_with_url_count;
"

run_psql_local() {
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" \
    -v ON_ERROR_STOP=1 "$@"
}

run_psql_k8s() {
  local pod
  # Prefer the exact Portal backend Postgres pod.
  pod="$(kubectl get pods -n portal -o name 2>/dev/null | sed 's#^pod/##' | awk '/^portal-portal-backend-postgresql-0$/ {print; exit}')"

  # Fallback: any pod that matches portal backend postgres naming.
  if [[ -z "$pod" ]]; then
    pod="$(kubectl get pods -n portal -o name 2>/dev/null | sed 's#^pod/##' | awk '/^portal-portal-backend-postgresql/ {print; exit}')"
  fi

  if [[ -z "$pod" ]]; then
    echo "Error: No se encontró pod PostgreSQL del portal en namespace 'portal'."
    return 1
  fi

  kubectl exec -n portal "$pod" -- sh -lc \
    "PSQL_BIN=\"\$(command -v psql 2>/dev/null || true)\"; \
     if [ -z \"\$PSQL_BIN\" ] && [ -x /opt/bitnami/postgresql/bin/psql ]; then PSQL_BIN=/opt/bitnami/postgresql/bin/psql; fi; \
     if [ -z \"\$PSQL_BIN\" ]; then echo 'Error: psql no encontrado en el pod PostgreSQL'; exit 127; fi; \
    PGPASSWORD='${DB_PASSWORD}' \"\$PSQL_BIN\" -U '${DB_USER}' -d '${DB_NAME}' -v ON_ERROR_STOP=1 $*"
}

MODE=""
if command -v psql >/dev/null 2>&1; then
  if run_psql_local -c "SELECT 1" >/dev/null 2>&1; then
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

echo "=============================================="
echo "Partner DB Check"
echo "=============================================="
echo "BPN: $BPN"
echo "Modo: $MODE"
if [[ "$MODE" == "local" ]]; then
  echo "DB: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
fi
echo

echo "[1/4] COMPANY"
echo "----------------------------------------------"
if [[ "$MODE" == "local" ]]; then
  run_psql_local -P pager=off -x -c "$SQL_COMPANY"
else
  run_psql_k8s "-P pager=off -x -c \"$SQL_COMPANY\""
fi

echo
echo "[2/4] USERS (company_users)"
echo "----------------------------------------------"
if [[ "$MODE" == "local" ]]; then
  run_psql_local -P pager=off -x -c "$SQL_USERS"
else
  run_psql_k8s "-P pager=off -x -c \"$SQL_USERS\""
fi

echo
echo "[3/4] CONNECTORS"
echo "----------------------------------------------"
if [[ "$MODE" == "local" ]]; then
  run_psql_local -P pager=off -x -c "$SQL_CONNECTORS"
else
  run_psql_k8s "-P pager=off -x -c \"$SQL_CONNECTORS\""
fi

echo
echo "[4/4] SUMMARY"
echo "----------------------------------------------"
if [[ "$MODE" == "local" ]]; then
  SUMMARY_RAW="$(run_psql_local -At -P pager=off -F '|' -c "$SQL_COUNTS")"
else
  SUMMARY_RAW="$(run_psql_k8s "-At -P pager=off -F '|' -c \"$SQL_COUNTS\"")"
fi

IFS='|' read -r COMPANY_COUNT USERS_COUNT CONNECTORS_COUNT CONNECTORS_WITH_URL_COUNT <<< "$SUMMARY_RAW"

COMPANY_COUNT="${COMPANY_COUNT:-0}"
USERS_COUNT="${USERS_COUNT:-0}"
CONNECTORS_COUNT="${CONNECTORS_COUNT:-0}"
CONNECTORS_WITH_URL_COUNT="${CONNECTORS_WITH_URL_COUNT:-0}"

echo "company_count: $COMPANY_COUNT"
echo "users_count: $USERS_COUNT"
echo "connectors_count: $CONNECTORS_COUNT"
echo "connectors_with_url_count: $CONNECTORS_WITH_URL_COUNT"
echo

if [[ "$COMPANY_COUNT" == "0" ]]; then
  echo "❌ RESULTADO: BPN no existe en portal.companies"
  exit 2
fi

if [[ "$USERS_COUNT" == "0" ]]; then
  echo "⚠️ RESULTADO: Existe company, pero no hay usuarios en portal.company_users"
fi

if [[ "$CONNECTORS_COUNT" == "0" ]]; then
  echo "⚠️ RESULTADO: Existe company, pero no hay registro en portal.connectors"
  exit 3
fi

if [[ "$CONNECTORS_WITH_URL_COUNT" == "0" ]]; then
  echo "⚠️ RESULTADO: Hay connectors, pero connector_url está vacío"
  exit 4
fi

echo "✅ RESULTADO: Partner correctamente configurado (company + users + connector_url)"
