#!/usr/bin/env bash
# =============================================================================
# append-bpn-in-configmap-ssi-dim-wallet-config.sh
#
# Añade un BPN adicional al campo SEED_WALLETS_BPN del configmap
# ssi-dim-wallet-config, conservando todos los BPNs existentes.
#
# ⚠️  ADVERTENCIA: Este patch es TEMPORAL.
#     Si el chart se vuelve a desplegar con Helm (helm upgrade), el configmap
#     se sobreescribirá con el valor definido en values.yaml y se perderá
#     el BPN añadido por este script.
#     Para hacer el cambio permanente, añade el BPN también en:
#       edc/charts/ssi-dim-wallet-stub/values.yaml
#       → wallet.seeding.bpnList
#
# -----------------------------------------------------------------------------
# Operación equivalente si quisieras sustituir la lista COMPLETA a mano:
#
#   CURRENT=$(kubectl get configmap ssi-dim-wallet-config -n portal \
#     -o jsonpath='{.data.SEED_WALLETS_BPN}')
#
#   kubectl patch configmap ssi-dim-wallet-config -n portal \
#     --type merge \
#     -p "{\"data\":{\"SEED_WALLETS_BPN\":\"${CURRENT},BPNL00000004PRTB\"}}"
#
#   kubectl rollout restart deployment/ssi-dim-wallet-stub -n portal
#
# Este script permite añadir un único BPN adicional de forma segura, sin
# necesidad de copiar la lista entera manualmente.
# -----------------------------------------------------------------------------
#
# Uso:
#   scripts/partner/append-bpn-in-configmap-ssi-dim-wallet-config.sh <BPN>
#
# Ejemplo:
#   scripts/partner/append-bpn-in-configmap-ssi-dim-wallet-config.sh BPNL00000003PRTA
# =============================================================================

set -euo pipefail

CONFIGMAP="ssi-dim-wallet-config"
NAMESPACE="portal"
FIELD="SEED_WALLETS_BPN"

# ─── Validar argumento ────────────────────────────────────────────────────────
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

# ─── Leer valor actual ────────────────────────────────────────────────────────
echo "Leyendo configmap '$CONFIGMAP' en namespace '$NAMESPACE'..."
CURRENT="$(kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath="{.data.${FIELD}}" 2>/dev/null || true)"

if [[ -z "$CURRENT" ]]; then
  echo "Error: No se encontró el campo '$FIELD' en el configmap '$CONFIGMAP'."
  echo "       Verifica que el configmap existe en el namespace '$NAMESPACE'."
  exit 1
fi

echo "  Valor actual de ${FIELD}:"
echo "  ${CURRENT}"
echo

# ─── Comprobar si ya existe ───────────────────────────────────────────────────
if echo ",$CURRENT," | grep -qiF ",${BPN},"; then
  echo "ℹ️  El BPN '$BPN' ya está en ${FIELD}. No se realizan cambios."
  exit 0
fi

# ─── Aplicar patch ────────────────────────────────────────────────────────────
NEW_VALUE="${CURRENT},${BPN}"

echo "Aplicando patch..."
echo "  Nuevo valor: ${NEW_VALUE}"
echo

kubectl patch configmap "$CONFIGMAP" -n "$NAMESPACE" \
  --type merge \
  -p "{\"data\":{\"${FIELD}\":\"${NEW_VALUE}\"}}"

echo
echo "✅ Configmap actualizado correctamente."
echo

# ─── Reiniciar wallet stub ────────────────────────────────────────────────────
echo "Reiniciando deployment/ssi-dim-wallet-stub para aplicar el nuevo seed..."
kubectl rollout restart deployment/ssi-dim-wallet-stub -n "$NAMESPACE"
echo
echo "⏳ Esperando a que el pod esté listo..."
kubectl rollout status deployment/ssi-dim-wallet-stub -n "$NAMESPACE" --timeout=120s
echo

# ─── Verificar resultado ──────────────────────────────────────────────────────
RESULT="$(kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" \
  -o jsonpath="{.data.${FIELD}}" 2>/dev/null)"
echo "✅ Valor final de ${FIELD}:"
echo "   ${RESULT}"
echo

echo "────────────────────────────────────────────────────────────"
echo "⚠️  RECUERDA: Este cambio es temporal."
echo "   Si se vuelve a desplegar el chart con Helm, se perderá."
echo "   Para hacerlo permanente, añade '$BPN' en:"
echo "   edc/charts/ssi-dim-wallet-stub/values.yaml"
echo "   → wallet.seeding.bpnList"
echo "────────────────────────────────────────────────────────────"
