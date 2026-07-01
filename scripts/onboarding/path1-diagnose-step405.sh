#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Script: path1-diagnose-step405.sh
# Fecha: 2026-06-30
#
# Problema:
# - El onboarding puede quedarse bloqueado en
#   INVITATION_UPDATE_CENTRAL_IDP_URLS (step 405) con mensaje Forbidden al
#   consultar el well-known del realm compartido.
#
# Solucion (Path 1 - causa raiz):
# - Diagnosticar el estado real del proceso, realm y configuracion de Keycloak
#   central/shared antes de forzar pasos de compensacion.
# - Verificar conectividad/logica sobre el well-known y estado del IDP en realm
#   central (CX-Central).
#
# Uso:
#   ./scripts/onboarding/path1-diagnose-step405.sh dataspace@partnera.com
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

echo "[1/7] Password DB"
PGPASSWORD_VALUE="$(kubectl get secret -n "$NS" portal-postgres -o jsonpath='{.data.portal-password}' | base64 -d)"

echo "[2/7] Proceso y realm de la invitacion"
INV_INFO="$(kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -t -A -F '|' -c "
SELECT ci.process_id, ci.idp_name
FROM portal.company_invitations ci
WHERE lower(ci.email)=lower('$EMAIL')
LIMIT 1;")"

PROCESS_ID="${INV_INFO%%|*}"
REALM_ALIAS="${INV_INFO##*|}"

if [[ -z "$PROCESS_ID" || -z "$REALM_ALIAS" ]]; then
  echo "No se pudo resolver process_id/idp_name para $EMAIL"
  exit 1
fi

echo "process_id=$PROCESS_ID"
echo "realm_alias=$REALM_ALIAS"

echo "[3/7] Steps 405/415"
kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -c "
SELECT ps.id, pst.label AS step_type, pss.label AS step_status, ps.date_created, ps.date_last_changed, ps.message
FROM portal.process_steps ps
JOIN portal.process_step_types pst ON pst.id=ps.process_step_type_id
JOIN portal.process_step_statuses pss ON pss.id=ps.process_step_status_id
WHERE ps.process_id='$PROCESS_ID' AND ps.process_step_type_id IN (405,415)
ORDER BY ps.date_created DESC;"

echo "[4/7] Leer config Keycloak desde cronjob portal-processes-worker"
CENTRAL_REALM="$(kubectl get cronjob portal-processes-worker -n "$NS" -o json | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].env[] | select(.name=="KEYCLOAK__CENTRAL__AUTHREALM") | .value')"
CENTRAL_URL="$(kubectl get cronjob portal-processes-worker -n "$NS" -o json | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].env[] | select(.name=="KEYCLOAK__CENTRAL__CONNECTIONSTRING") | .value')"
SHARED_URL="$(kubectl get cronjob portal-processes-worker -n "$NS" -o json | jq -r '.spec.jobTemplate.spec.template.spec.containers[0].env[] | select(.name=="KEYCLOAK__SHARED__CONNECTIONSTRING") | .value')"

echo "central_realm=$CENTRAL_REALM"
echo "central_url=$CENTRAL_URL"
echo "shared_url=$SHARED_URL"

echo "[5/7] Probar well-known del realm compartido"
WELLKNOWN_URL="$SHARED_URL/auth/realms/$REALM_ALIAS/.well-known/openid-configuration"
HTTP_CODE="$(curl -s -o /tmp/path1_wk.json -w "%{http_code}" "$WELLKNOWN_URL")"
echo "wellknown_http=$HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "well-known OK"
else
  echo "well-known no OK. Body:"
  cat /tmp/path1_wk.json
fi

echo "[6/7] Estado de IDP en realm central"
ADMIN_PASS="$(kubectl get secret -n "$NS" portal-centralidp -o jsonpath='{.data.admin-password}' | base64 -d)"
CENTRAL_TOKEN="$(curl -s -X POST "$CENTRAL_URL/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" -d "client_id=admin-cli" -d "username=admin" -d "password=$ADMIN_PASS" | jq -r '.access_token')"

IDP_HTTP="$(curl -s -o /tmp/path1_idp.json -w "%{http_code}" \
  -H "Authorization: Bearer $CENTRAL_TOKEN" \
  "$CENTRAL_URL/auth/admin/realms/$CENTRAL_REALM/identity-provider/instances/$REALM_ALIAS")"

echo "central_idp_instance_http=$IDP_HTTP"
if [[ "$IDP_HTTP" == "200" ]]; then
  jq '{alias,providerId,enabled,config:{authorizationUrl:.config.authorizationUrl,tokenUrl:.config.tokenUrl,logoutUrl:.config.logoutUrl,userInfoUrl:.config.userInfoUrl,jwksUrl:.config.jwksUrl}}' /tmp/path1_idp.json
else
  echo "respuesta central-idp:"
  cat /tmp/path1_idp.json
fi

echo "[7/7] Mailing asociado"
kubectl exec -n "$NS" "$PGPOD" -- env PGPASSWORD="$PGPASSWORD_VALUE" psql -U "$DBU" -d "$DBN" -c "
SELECT ci.email, ci.process_id, mi.id AS mailing_id, ms.label AS mailing_status
FROM portal.company_invitations ci
LEFT JOIN portal.mailing_informations mi ON mi.process_id = ci.process_id
LEFT JOIN portal.mailing_statuses ms ON ms.id = mi.mailing_status_id
WHERE lower(ci.email)=lower('$EMAIL');"

echo "Diagnostico Path1 completado"
