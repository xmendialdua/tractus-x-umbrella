#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: path1-fix-ssl-and-retry.sh
# Fecha: 2026-06-30
#
# Problema:
# - El onboarding se bloquea en INVITATION_UPDATE_CENTRAL_IDP_URLS (step 405)
#   con error Forbidden al consultar el well-known del realm compartido.
# - En este entorno, el realm invitado puede quedar con sslRequired=external,
#   provocando 403 en llamadas HTTP desde la ruta usada por el worker.
#
# Solucion (Path 1 - causa raiz):
# - Ajustar sslRequired=none en el realm compartido del partner.
# - Reintentar de forma limpia el step 405 usando path1-retry-step405.sh.
#
#   Una vez desde el portal se realiza la invitación para el partner, 
#   hay que ejecutar este script para corregir el sslRequired y reintentar 
#   la generación del usuario central-idp y así poder continuar con el proceso 
#   y pueden llegar los mensajes al stmp4dev.
#
# Uso:
#   ./scripts/onboarding/path1-fix-ssl-and-retry.sh dataspace@partnera.com
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

echo "[1/4] Resolver realm (idp_name) para $EMAIL"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NS" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"
REALM_ALIAS="$(kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" \
  psql -U "$DBU" -d "$DBN" -t -A -c "
SELECT ci.idp_name
FROM portal.company_invitations ci
WHERE lower(ci.email)=lower('$EMAIL')
LIMIT 1;")"

if [[ -z "$REALM_ALIAS" ]]; then
  echo "No se pudo resolver idp_name para $EMAIL"
  exit 1
fi

echo "realm_alias=$REALM_ALIAS"

echo "[2/4] Obtener token admin de sharedidp"
ADMIN_PASS="$(kubectl get secret -n "$NS" portal-sharedidp -o jsonpath='{.data.admin-password}' | base64 -d)"
TOKEN="$(curl -s -X POST "http://sharedidp.51.178.94.25.nip.io/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=${ADMIN_PASS}" | jq -r '.access_token')"

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "No se pudo obtener token admin de sharedidp"
  exit 1
fi

echo "[3/4] Ajustar sslRequired=none en realm $REALM_ALIAS"
CURRENT_SSL="$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/${REALM_ALIAS}" | jq -r '.sslRequired')"
echo "sslRequired actual: $CURRENT_SSL"

curl -s -o /tmp/path1_fix_ssl_response.txt -w "%{http_code}" \
  -X PUT "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/${REALM_ALIAS}" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"realm\":\"${REALM_ALIAS}\",\"enabled\":true,\"sslRequired\":\"none\"}" > /tmp/path1_fix_ssl_code.txt

HTTP_CODE="$(cat /tmp/path1_fix_ssl_code.txt)"
if [[ "$HTTP_CODE" != "204" ]]; then
  echo "Error al actualizar sslRequired (HTTP $HTTP_CODE)"
  cat /tmp/path1_fix_ssl_response.txt
  exit 1
fi

NEW_SSL="$(curl -s -H "Authorization: Bearer ${TOKEN}" \
  "http://sharedidp.51.178.94.25.nip.io/auth/admin/realms/${REALM_ALIAS}" | jq -r '.sslRequired')"
echo "sslRequired nuevo: $NEW_SSL"

echo "[4/4] Reintentar step 405 de forma limpia"
"$SCRIPT_DIR/path1-retry-step405.sh" "$EMAIL"
