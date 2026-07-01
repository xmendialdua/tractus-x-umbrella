#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="portal"
POD="portal-portal-backend-postgresql-0"
PGUSER="portal"
PGPASSWORD="dbpasswordportal"
PGDATABASE="postgres"

BPN_VALUE="${1:-}"
COMPANY_NAME="${2:-}"

if [[ -z "$BPN_VALUE" || -z "$COMPANY_NAME" ]]; then
  echo "Uso: $0 <BPN_VALUE> <COMPANY_NAME>"
  echo "Ejemplo: $0 BPNL00000000MASS MondragonAssembly"
  exit 1
fi

# Escape single quotes for safe SQL string literals.
SQL_BPN_VALUE="${BPN_VALUE//\'/\'\'}"
SQL_COMPANY_NAME="${COMPANY_NAME//\'/\'\'}"

kubectl exec -n "$NAMESPACE" "$POD" -- \
  env PGPASSWORD="$PGPASSWORD" \
  psql -v ON_ERROR_STOP=1 \
    -U "$PGUSER" \
    -d "$PGDATABASE" \
    -c "
    UPDATE portal.companies
    SET business_partner_number = '$SQL_BPN_VALUE'
    WHERE name = '$SQL_COMPANY_NAME';
    "

echo "BPN actualizado para COMPANY_NAME='$COMPANY_NAME' con BPN_VALUE='$BPN_VALUE'"