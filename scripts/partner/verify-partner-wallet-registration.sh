#!/usr/bin/env bash
# =============================================================================
# verify-wallet-registration.sh
#
# Verifica que un partner (BPN) está correctamente registrado en el wallet stub:
#   1. Que el BPN aparece en SEED_WALLETS_BPN del configmap ssi-dim-wallet-config.
#   2. Que el wallet stub emite un token OAuth con el claim bpn=<BPN> correcto.
#
# Uso:
#   scripts/partner/verify-partner-wallet-registration.sh BPNL00000003PRTA
#
# Salida final:
#   ✅ OK   — ambas comprobaciones pasaron
#   ❌ NOT OK — indica exactamente qué falta configurar
# =============================================================================

set -euo pipefail

BPN="${1:-}"
if [[ -z "$BPN" ]]; then
  echo "Uso: $0 <BPN>"
  echo "Ejemplo: $0 BPNL00000003PRTA"
  exit 1
fi

if [[ ! "$BPN" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "Error: BPN contiene caracteres no válidos: $BPN"
  exit 1
fi

# Derivar prefijo de conector a partir de los últimos 4 caracteres del BPN
CONNECTOR_PREFIX="$(echo "${BPN: -4}" | tr '[:upper:]' '[:lower:]')"
VAULT_POD="${CONNECTOR_PREFIX}-edc-vault-0"

# Namespaces
PORTAL_NS="portal"
UMBRELLA_NS="umbrella"

# Nombre del configmap y clave del campo
WALLET_CONFIGMAP="ssi-dim-wallet-config"
SEED_FIELD="SEED_WALLETS_BPN"

# Secreto en Vault que usa el conector para autenticarse con el wallet stub
VAULT_SECRET_ALIAS="edc-wallet-secret"

# ─────────────────────────────────────────────────────────────────────────────
# Utilidades
# ─────────────────────────────────────────────────────────────────────────────
ok()    { echo "   ✅ $*"; }
fail()  { echo "   ❌ $*"; }
info()  { echo "   ℹ️  $*"; }
header(){ echo; echo "══════════════════════════════════════════════"; echo "  $*"; echo "══════════════════════════════════════════════"; }

RESULT_CHECK1="SKIP"
RESULT_CHECK2="SKIP"
MSG_CHECK1=""
MSG_CHECK2=""

# ─────────────────────────────────────────────────────────────────────────────
# Preámbulo
# ─────────────────────────────────────────────────────────────────────────────
header "Verificación de wallet — $BPN"
echo "  Conector derivado : $CONNECTOR_PREFIX"
echo "  Vault pod          : $VAULT_POD  (namespace: $UMBRELLA_NS)"
echo "  Configmap          : $WALLET_CONFIGMAP  (namespace: $PORTAL_NS)"

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 1: BPN en SEED_WALLETS_BPN
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 1 — BPN en SEED_WALLETS_BPN"

SEED_VALUE=""
if ! SEED_VALUE="$(kubectl get configmap "$WALLET_CONFIGMAP" -n "$PORTAL_NS" \
    -o jsonpath="{.data.${SEED_FIELD}}" 2>/dev/null)"; then
  fail "No se pudo leer el configmap '$WALLET_CONFIGMAP' en namespace '$PORTAL_NS'."
  RESULT_CHECK1="FAIL"
  MSG_CHECK1="Configmap '$WALLET_CONFIGMAP' no encontrado en namespace '$PORTAL_NS'."
else
  echo "  Valor actual de ${SEED_FIELD}:"
  echo "  ${SEED_VALUE}"
  echo

  # Verificar que el BPN está en la lista (separada por comas)
  if echo ",$SEED_VALUE," | grep -qiF ",${BPN},"; then
    ok "El BPN '$BPN' SÍ está en ${SEED_FIELD}."
    RESULT_CHECK1="OK"
  else
    fail "El BPN '$BPN' NO está en ${SEED_FIELD}."
    RESULT_CHECK1="FAIL"
    MSG_CHECK1="Añade '$BPN' a ${SEED_FIELD} en el configmap '$WALLET_CONFIGMAP' y reinicia el pod del wallet stub."
    info "Comando:"
    info "  kubectl patch configmap $WALLET_CONFIGMAP -n $PORTAL_NS \\"
    info "    --type merge \\"
    info "    -p '{\"data\":{\"${SEED_FIELD}\":\"${SEED_VALUE},${BPN}\"}}'"
    info "  kubectl rollout restart deployment/ssi-dim-wallet-stub -n $PORTAL_NS"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# CHECK 2: Wallet stub emite token con bpn=<BPN>
# ─────────────────────────────────────────────────────────────────────────────
header "CHECK 2 — Wallet stub emite VC con bpn=$BPN"

# 2a. Obtener client secret del Vault del conector
CLIENT_SECRET=""
echo "  Obteniendo client secret de Vault ($VAULT_POD)..."

if ! kubectl get pod "$VAULT_POD" -n "$UMBRELLA_NS" >/dev/null 2>&1; then
  fail "Pod de Vault '$VAULT_POD' no encontrado en namespace '$UMBRELLA_NS'."
  RESULT_CHECK2="FAIL"
  MSG_CHECK2="Pod de Vault '$VAULT_POD' no existe. Revisa el despliegue del conector $CONNECTOR_PREFIX."
else
  CLIENT_SECRET="$(kubectl exec -n "$UMBRELLA_NS" "$VAULT_POD" -- \
    vault kv get -field=content "secret/$VAULT_SECRET_ALIAS" 2>/dev/null || true)"

  if [[ -z "$CLIENT_SECRET" ]]; then
    fail "No se encontró el secreto '$VAULT_SECRET_ALIAS' en Vault ($VAULT_POD)."
    RESULT_CHECK2="FAIL"
    MSG_CHECK2="Carga el secreto 'edc-wallet-secret' en el Vault del conector $CONNECTOR_PREFIX:
    kubectl exec -n $UMBRELLA_NS $VAULT_POD -- \\
      vault kv put secret/edc-wallet-secret content=<valor>"
  else
    info "Client secret obtenido (${#CLIENT_SECRET} chars)."

    # 2b. Obtener token OAuth desde el wallet stub
    WALLET_POD_ID="$(kubectl get pods -n "$PORTAL_NS" -l app=ssi-dim-wallet-stub \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

    if [[ -z "$WALLET_POD_ID" ]]; then
      fail "No se encontró pod del wallet stub (app=ssi-dim-wallet-stub) en namespace '$PORTAL_NS'."
      RESULT_CHECK2="FAIL"
      MSG_CHECK2="Pod del wallet stub no encontrado en namespace '$PORTAL_NS'."
    else
      echo "  Solicitando token OAuth al wallet stub ($WALLET_POD_ID)..."

      TOKEN_RESPONSE="$(kubectl exec -n "$PORTAL_NS" "$WALLET_POD_ID" -- sh -c \
        "wget -qO- --post-data='grant_type=client_credentials&client_id=${BPN}&client_secret=${CLIENT_SECRET}' \
         'http://localhost:8080/oauth/token' 2>/dev/null" 2>/dev/null || true)"

      if [[ -z "$TOKEN_RESPONSE" ]]; then
        fail "No se obtuvo respuesta del endpoint /oauth/token del wallet stub."
        RESULT_CHECK2="FAIL"
        MSG_CHECK2="El wallet stub no respondió al intento de OAuth para '$BPN'. Comprueba que el pod del wallet stub está Running."

      elif echo "$TOKEN_RESPONSE" | grep -q '"error"'; then
        ERROR_MSG="$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error_description', d.get('error','desconocido')))" 2>/dev/null || echo "$TOKEN_RESPONSE")"
        fail "El wallet stub devolvió un error OAuth: $ERROR_MSG"
        RESULT_CHECK2="FAIL"
        MSG_CHECK2="El wallet stub rechazó la solicitud OAuth para '$BPN'. Causa: $ERROR_MSG
    Probablemente '$BPN' no está en SEED_WALLETS_BPN (ver CHECK 1)."

      else
        # 2c. Decodificar JWT y verificar claim bpn
        ACCESS_TOKEN="$(echo "$TOKEN_RESPONSE" | python3 -c \
          "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || true)"

        if [[ -z "$ACCESS_TOKEN" ]]; then
          fail "Token recibido pero no se pudo extraer access_token."
          RESULT_CHECK2="FAIL"
          MSG_CHECK2="Respuesta inesperada del wallet stub: $TOKEN_RESPONSE"
        else
          # Decodificar el payload del JWT (segunda parte, base64url)
          JWT_PAYLOAD_B64="$(echo "$ACCESS_TOKEN" | cut -d. -f2)"
          # Añadir padding si es necesario
          PAD="$(( (4 - ${#JWT_PAYLOAD_B64} % 4) % 4 ))"
          for ((i=0; i<PAD; i++)); do JWT_PAYLOAD_B64="${JWT_PAYLOAD_B64}="; done
          JWT_PAYLOAD_B64="${JWT_PAYLOAD_B64//-/+}"
          JWT_PAYLOAD_B64="${JWT_PAYLOAD_B64//_//}"

          PAYLOAD_JSON="$(echo "$JWT_PAYLOAD_B64" | base64 -d 2>/dev/null || true)"
          BPN_CLAIM="$(echo "$PAYLOAD_JSON" | python3 -c \
            "import sys,json; print(json.load(sys.stdin).get('bpn',''))" 2>/dev/null || true)"

          echo "  Claims relevantes del JWT emitido:"
          echo "$PAYLOAD_JSON" | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  for k in ['bpn','sub','iss','aud','exp']:
    if k in d:
      print(f'     {k:6}: {d[k]}')
except:
  pass
" 2>/dev/null

          if [[ "$BPN_CLAIM" == "$BPN" ]]; then
            ok "El JWT contiene claim bpn='$BPN_CLAIM' — correcto."
            RESULT_CHECK2="OK"
          elif [[ -z "$BPN_CLAIM" ]]; then
            fail "El JWT NO contiene el claim 'bpn'."
            RESULT_CHECK2="FAIL"
            MSG_CHECK2="El wallet stub emite tokens para '$BPN' pero sin claim 'bpn'. Verifica la versión y configuración del wallet stub."
          else
            fail "El JWT contiene bpn='$BPN_CLAIM' pero se esperaba '$BPN'."
            RESULT_CHECK2="FAIL"
            MSG_CHECK2="El wallet emite tokens con BPN incorrecto: '$BPN_CLAIM' en lugar de '$BPN'.
    Puede que el BPN configurado en el conector no coincida con el registrado en el wallet."
          fi
        fi
      fi
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────────────────────────────────────
header "RESULTADO FINAL"

ALL_OK=true
[[ "$RESULT_CHECK1" != "OK" ]] && ALL_OK=false
[[ "$RESULT_CHECK2" != "OK" ]] && ALL_OK=false

echo "  CHECK 1 (SEED_WALLETS_BPN)    : $RESULT_CHECK1"
echo "  CHECK 2 (VC claim bpn=<BPN>)  : $RESULT_CHECK2"
echo

if [[ "$ALL_OK" == "true" ]]; then
  echo "✅ OK — El partner '$BPN' está correctamente registrado en el wallet stub."
  exit 0
else
  echo "❌ NOT OK — Configuración incompleta para '$BPN':"
  echo
  if [[ "$RESULT_CHECK1" != "OK" && -n "$MSG_CHECK1" ]]; then
    echo "  [CHECK 1] $MSG_CHECK1"
    echo
  fi
  if [[ "$RESULT_CHECK2" != "OK" && -n "$MSG_CHECK2" ]]; then
    echo "  [CHECK 2] $MSG_CHECK2"
    echo
  fi
  exit 1
fi
