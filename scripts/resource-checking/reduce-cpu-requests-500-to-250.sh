#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Script: reduce-cpu-requests-500-to-250.sh
#
# Objetivo:
# - Bajar request de CPU de 500m a 250m en workloads seleccionados.
# - Solo modifica contenedores cuyo request actual sea exactamente 500m.
#
# Uso:
# 1) Edita la lista SELECTED_TARGETS (bloque de configuracion).
# 2) Ejecuta en dry-run (por defecto):
#      ./scripts/resource-checking/reduce-cpu-requests-500-to-250.sh
# 3) Para aplicar cambios reales:
#      APPLY_CHANGES=true ./scripts/resource-checking/reduce-cpu-requests-500-to-250.sh
# -----------------------------------------------------------------------------

# ------------------------- CONFIGURACION INICIAL ------------------------------
FROM_CPU_REQUEST="${FROM_CPU_REQUEST:-500m}"
TO_CPU_REQUEST="${TO_CPU_REQUEST:-250m}"
APPLY_CHANGES="${APPLY_CHANGES:-false}"
WAIT_ROLLOUT="${WAIT_ROLLOUT:-true}"

# Lista de workloads disponibles (keys):
# - smtp4dev
# - bdrs-server
# - ssi-dim-wallet-stub
# - portal-centralidp
# - portal-sharedidp
# - portal-selfdescription
#
# Deja aqui SOLO los que quieras cambiar en esta ejecucion:
SELECTED_TARGETS=(
  "ssi-dim-wallet-stub"
)
# -----------------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"

if [[ -z "${KUBECONFIG:-}" && -f "$REPO_KUBECONFIG" ]]; then
  export KUBECONFIG="$REPO_KUBECONFIG"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl no esta instalado o no esta en PATH"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq es requerido para este script"
  exit 1
fi

declare -A TARGET_NAMESPACE
declare -A TARGET_KIND
declare -A TARGET_NAME

TARGET_NAMESPACE["smtp4dev"]="portal"
TARGET_KIND["smtp4dev"]="deployment"
TARGET_NAME["smtp4dev"]="smtp4dev"

TARGET_NAMESPACE["bdrs-server"]="portal"
TARGET_KIND["bdrs-server"]="deployment"
TARGET_NAME["bdrs-server"]="bdrs-server"

TARGET_NAMESPACE["ssi-dim-wallet-stub"]="portal"
TARGET_KIND["ssi-dim-wallet-stub"]="deployment"
TARGET_NAME["ssi-dim-wallet-stub"]="ssi-dim-wallet-stub"

TARGET_NAMESPACE["portal-centralidp"]="portal"
TARGET_KIND["portal-centralidp"]="statefulset"
TARGET_NAME["portal-centralidp"]="portal-centralidp"

TARGET_NAMESPACE["portal-sharedidp"]="portal"
TARGET_KIND["portal-sharedidp"]="statefulset"
TARGET_NAME["portal-sharedidp"]="portal-sharedidp"

TARGET_NAMESPACE["portal-selfdescription"]="portal"
TARGET_KIND["portal-selfdescription"]="deployment"
TARGET_NAME["portal-selfdescription"]="portal-selfdescription"

if [[ ${#SELECTED_TARGETS[@]} -eq 0 ]]; then
  echo "ERROR: SELECTED_TARGETS esta vacio"
  exit 1
fi

echo "==============================================="
echo "CPU Request Tuning: $FROM_CPU_REQUEST -> $TO_CPU_REQUEST"
echo "==============================================="
echo "KUBECONFIG: ${KUBECONFIG:-no-definido}"
echo "APPLY_CHANGES: $APPLY_CHANGES"
echo "WAIT_ROLLOUT: $WAIT_ROLLOUT"
echo ""

if [[ "$APPLY_CHANGES" != "true" ]]; then
  echo "MODO DRY-RUN: no se aplicaran cambios reales"
  echo "Para aplicar: APPLY_CHANGES=true $0"
  echo ""
fi

for key in "${SELECTED_TARGETS[@]}"; do
  ns="${TARGET_NAMESPACE[$key]:-}"
  kind="${TARGET_KIND[$key]:-}"
  name="${TARGET_NAME[$key]:-}"

  if [[ -z "$ns" || -z "$kind" || -z "$name" ]]; then
    echo "ERROR: target '$key' no definido en el mapa de workloads"
    exit 1
  fi

  echo "-----------------------------------------------"
  echo "Target: $key"
  echo "Resource: $kind/$name (ns=$ns)"

  if ! current_json="$(kubectl get "$kind" "$name" -n "$ns" -o json 2>/dev/null)"; then
    echo "ERROR: no se encontro recurso $kind/$name en namespace $ns"
    exit 1
  fi

  candidates="$(echo "$current_json" | jq -r --arg from "$FROM_CPU_REQUEST" '
    .spec.template.spec.containers[]
    | select((.resources.requests.cpu // "") == $from)
    | .name
  ')"

  if [[ -z "$candidates" ]]; then
    echo "Sin cambios: ningun contenedor con request CPU=$FROM_CPU_REQUEST"
    continue
  fi

  echo "Contenedores a modificar:"
  while IFS= read -r c; do
    [[ -n "$c" ]] && echo "  - $c"
  done <<< "$candidates"

  patched_json="$(echo "$current_json" | jq --arg from "$FROM_CPU_REQUEST" --arg to "$TO_CPU_REQUEST" '
    .spec.template.spec.containers |= map(
      if (.resources.requests.cpu // "") == $from
      then (.resources.requests.cpu = $to)
      else .
      end
    )
  ')"

  if [[ "$APPLY_CHANGES" == "true" ]]; then
    echo "$patched_json" | kubectl apply -f - >/dev/null
    echo "Aplicado: request CPU actualizado en $kind/$name"

    if [[ "$WAIT_ROLLOUT" == "true" ]]; then
      echo "Esperando rollout..."
      kubectl rollout status "$kind/$name" -n "$ns" --timeout=180s
    fi
  else
    echo "DRY-RUN: cambio preparado pero no aplicado"
  fi
done

echo ""
echo "Proceso finalizado"
