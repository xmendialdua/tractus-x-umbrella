#!/usr/bin/env bash

set -euo pipefail

# Optional thresholds (override with env vars if needed)
RUNTIME_YELLOW_PCT="${RUNTIME_YELLOW_PCT:-70}"
RUNTIME_RED_PCT="${RUNTIME_RED_PCT:-85}"
REQUESTS_YELLOW_PCT="${REQUESTS_YELLOW_PCT:-70}"
REQUESTS_RED_PCT="${REQUESTS_RED_PCT:-85}"
LIMITS_YELLOW_PCT="${LIMITS_YELLOW_PCT:-90}"
LIMITS_RED_PCT="${LIMITS_RED_PCT:-100}"
FREE_CPU_YELLOW_M="${FREE_CPU_YELLOW_M:-500}"
FREE_CPU_RED_M="${FREE_CPU_RED_M:-200}"
LOW_UTILIZATION_PCT="${LOW_UTILIZATION_PCT:-25}"
MIN_REQUEST_CPU_M="${MIN_REQUEST_CPU_M:-100}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO_KUBECONFIG="$REPO_ROOT/kubeconfig.yaml"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/scripts/resource-checking/reports}"

if [[ -z "${KUBECONFIG:-}" && -f "$REPO_KUBECONFIG" ]]; then
  export KUBECONFIG="$REPO_KUBECONFIG"
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl no esta instalado o no esta en PATH"
  exit 1
fi

if ! kubectl version --client >/dev/null 2>&1; then
  echo "ERROR: kubectl no responde correctamente"
  exit 1
fi

to_int() {
  local value="$1"
  echo "$value" | tr -d '%' | awk '{print int($1)}'
}

cpu_to_m() {
  local raw="$1"
  if [[ "$raw" =~ m$ ]]; then
    echo "${raw%m}"
  else
    awk -v v="$raw" 'BEGIN {printf "%d", v*1000}'
  fi
}

cpu_str_to_m() {
  local raw="$1"
  if [[ -z "$raw" || "$raw" == "0" ]]; then
    echo 0
  elif [[ "$raw" =~ m$ ]]; then
    echo "${raw%m}"
  else
    awk -v v="$raw" 'BEGIN {printf "%d", v*1000}'
  fi
}

severity_from_pct() {
  local pct="$1"
  local yellow="$2"
  local red="$3"

  if (( pct >= red )); then
    echo "RED"
  elif (( pct >= yellow )); then
    echo "YELLOW"
  else
    echo "GREEN"
  fi
}

severity_rank() {
  local sev="$1"
  case "$sev" in
    GREEN) echo 0 ;;
    YELLOW) echo 1 ;;
    RED) echo 2 ;;
    *) echo 1 ;;
  esac
}

max_severity() {
  local current="$1"
  local candidate="$2"
  if (( $(severity_rank "$candidate") > $(severity_rank "$current") )); then
    echo "$candidate"
  else
    echo "$current"
  fi
}

overall="GREEN"
RUN_TS="$(date -u +%Y%m%dT%H%M%SZ)"

mkdir -p "$OUTPUT_DIR"

RUNTIME_CSV="$OUTPUT_DIR/runtime_nodes_${RUN_TS}.csv"
REQUESTS_CSV="$OUTPUT_DIR/requests_limits_nodes_${RUN_TS}.csv"
FREE_CPU_CSV="$OUTPUT_DIR/free_cpu_by_node_${RUN_TS}.csv"
TOP_REQ_CSV="$OUTPUT_DIR/top_cpu_requests_${RUN_TS}.csv"
CANDIDATES_CSV="$OUTPUT_DIR/tuning_candidates_${RUN_TS}.csv"
CONNECTOR_CSV="$OUTPUT_DIR/connector_estimate_${RUN_TS}.csv"
SUMMARY_CSV="$OUTPUT_DIR/summary_${RUN_TS}.csv"

echo "timestamp,node,cpu_raw,cpu_pct,mem_raw,mem_pct,semaphore" > "$RUNTIME_CSV"
echo "timestamp,node,cpu_req_pct,cpu_lim_pct,mem_req_pct,mem_lim_pct,semaphore" > "$REQUESTS_CSV"
echo "timestamp,node,alloc_cpu_m,req_cpu_m,free_cpu_m,semaphore" > "$FREE_CPU_CSV"
echo "timestamp,namespace,pod,cpu_req_m" > "$TOP_REQ_CSV"
echo "timestamp,namespace,pod,cpu_req_m,cpu_use_m,use_pct_of_request" > "$CANDIDATES_CSV"
echo "timestamp,ikln_cpu_req_m,mass_cpu_req_m,profile_cpu_req_m,cluster_free_cpu_m,estimated_additional,semaphore" > "$CONNECTOR_CSV"
echo "timestamp,section,status,value" > "$SUMMARY_CSV"

echo "==============================================="
echo "Cluster Resource Check"
echo "==============================================="
echo "Fecha: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "KUBECONFIG: ${KUBECONFIG:-no-definido}"
echo ""

echo "[1/5] Uso runtime por nodo (kubectl top nodes)"
if ! TOP_NODES_RAW="$(kubectl top nodes --no-headers 2>/dev/null)"; then
  echo "ERROR: no se pudieron obtener metricas de nodos (kubectl top nodes)."
  echo "Asegura que metrics-server esta disponible."
  exit 1
fi

if [[ -z "$TOP_NODES_RAW" ]]; then
  echo "ERROR: kubectl top nodes no devolvio datos"
  exit 1
fi

runtime_status="GREEN"
max_runtime_cpu=0
max_runtime_mem=0

printf '%-38s %-8s %-8s %-12s %-12s %-8s\n' "NODE" "CPU" "CPU%" "MEM" "MEM%" "SEMAFORO"
while IFS= read -r line; do
  node_name="$(echo "$line" | awk '{print $1}')"
  cpu_raw="$(echo "$line" | awk '{print $2}')"
  cpu_pct_raw="$(echo "$line" | awk '{print $3}')"
  mem_raw="$(echo "$line" | awk '{print $4}')"
  mem_pct_raw="$(echo "$line" | awk '{print $5}')"

  cpu_pct="$(to_int "$cpu_pct_raw")"
  mem_pct="$(to_int "$mem_pct_raw")"

  if (( cpu_pct > max_runtime_cpu )); then max_runtime_cpu="$cpu_pct"; fi
  if (( mem_pct > max_runtime_mem )); then max_runtime_mem="$mem_pct"; fi

  node_cpu_sev="$(severity_from_pct "$cpu_pct" "$RUNTIME_YELLOW_PCT" "$RUNTIME_RED_PCT")"
  node_mem_sev="$(severity_from_pct "$mem_pct" "$RUNTIME_YELLOW_PCT" "$RUNTIME_RED_PCT")"
  node_sev="$(max_severity "$node_cpu_sev" "$node_mem_sev")"
  runtime_status="$(max_severity "$runtime_status" "$node_sev")"

  printf '%-38s %-8s %-8s %-12s %-12s %-8s\n' "$node_name" "$cpu_raw" "$cpu_pct_raw" "$mem_raw" "$mem_pct_raw" "$node_sev"
  echo "$RUN_TS,$node_name,$cpu_raw,$cpu_pct,$mem_raw,$mem_pct,$node_sev" >> "$RUNTIME_CSV"
done <<< "$TOP_NODES_RAW"

echo "Runtime max CPU: ${max_runtime_cpu}%"
echo "Runtime max MEM: ${max_runtime_mem}%"
echo "Semaforo runtime: $runtime_status"
echo ""
overall="$(max_severity "$overall" "$runtime_status")"
echo "$RUN_TS,runtime_status,$runtime_status,max_cpu=${max_runtime_cpu};max_mem=${max_runtime_mem}" >> "$SUMMARY_CSV"

echo "[2/5] Recursos asignados (requests/limits) por nodo"
requests_limits_status="GREEN"
printf '%-38s %-10s %-10s %-10s %-10s %-8s\n' "NODE" "CPU_REQ%" "CPU_LIM%" "MEM_REQ%" "MEM_LIM%" "SEMAFORO"

while IFS= read -r node; do
  desc="$(kubectl describe node "$node")"

  cpu_line="$(awk '/Allocated resources:/{flag=1;next}/Events:/{flag=0}flag && $1=="cpu"{print;exit}' <<< "$desc")"
  mem_line="$(awk '/Allocated resources:/{flag=1;next}/Events:/{flag=0}flag && $1=="memory"{print;exit}' <<< "$desc")"

  cpu_req="0"
  cpu_lim="0"
  mem_req="0"
  mem_lim="0"

  if [[ -n "$cpu_line" ]]; then
    cpu_req_match="$(echo "$cpu_line" | grep -oE '\([0-9]+%\)' | sed -n '1p' | tr -d '()%')"
    cpu_lim_match="$(echo "$cpu_line" | grep -oE '\([0-9]+%\)' | sed -n '2p' | tr -d '()%')"
    cpu_req="${cpu_req_match:-0}"
    cpu_lim="${cpu_lim_match:-0}"
  fi

  if [[ -n "$mem_line" ]]; then
    mem_req_match="$(echo "$mem_line" | grep -oE '\([0-9]+%\)' | sed -n '1p' | tr -d '()%')"
    mem_lim_match="$(echo "$mem_line" | grep -oE '\([0-9]+%\)' | sed -n '2p' | tr -d '()%')"
    mem_req="${mem_req_match:-0}"
    mem_lim="${mem_lim_match:-0}"
  fi

  sev_cpu_req="$(severity_from_pct "$cpu_req" "$REQUESTS_YELLOW_PCT" "$REQUESTS_RED_PCT")"
  sev_mem_req="$(severity_from_pct "$mem_req" "$REQUESTS_YELLOW_PCT" "$REQUESTS_RED_PCT")"
  sev_cpu_lim="$(severity_from_pct "$cpu_lim" "$LIMITS_YELLOW_PCT" "$LIMITS_RED_PCT")"
  sev_mem_lim="$(severity_from_pct "$mem_lim" "$LIMITS_YELLOW_PCT" "$LIMITS_RED_PCT")"

  node_sev="GREEN"
  node_sev="$(max_severity "$node_sev" "$sev_cpu_req")"
  node_sev="$(max_severity "$node_sev" "$sev_mem_req")"
  node_sev="$(max_severity "$node_sev" "$sev_cpu_lim")"
  node_sev="$(max_severity "$node_sev" "$sev_mem_lim")"

  requests_limits_status="$(max_severity "$requests_limits_status" "$node_sev")"

  printf '%-38s %-10s %-10s %-10s %-10s %-8s\n' "$node" "${cpu_req}%" "${cpu_lim}%" "${mem_req}%" "${mem_lim}%" "$node_sev"
  echo "$RUN_TS,$node,$cpu_req,$cpu_lim,$mem_req,$mem_lim,$node_sev" >> "$REQUESTS_CSV"
done < <(kubectl get nodes -o name | sed 's|node/||')

echo "Semaforo requests/limits: $requests_limits_status"
echo ""
overall="$(max_severity "$overall" "$requests_limits_status")"
echo "$RUN_TS,requests_limits_status,$requests_limits_status,na" >> "$SUMMARY_CSV"

echo "[3/5] Pods en Pending"
pending_count="$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')"
pending_status="GREEN"
if (( pending_count > 0 && pending_count <= 3 )); then
  pending_status="YELLOW"
elif (( pending_count > 3 )); then
  pending_status="RED"
fi
echo "Pending pods: $pending_count"
echo "Semaforo pending: $pending_status"
if (( pending_count > 0 )); then
  kubectl get pods -A --field-selector=status.phase=Pending
fi
echo ""
overall="$(max_severity "$overall" "$pending_status")"
echo "$RUN_TS,pending_status,$pending_status,pending_count=$pending_count" >> "$SUMMARY_CSV"

echo "[4/5] Eventos de scheduling recientes"
failed_sched_count="$(kubectl get events -A --sort-by=.lastTimestamp 2>/dev/null | grep -Eic 'FailedScheduling|Insufficient cpu|Insufficient memory' || true)"
sched_status="GREEN"
if (( failed_sched_count > 0 && failed_sched_count <= 5 )); then
  sched_status="YELLOW"
elif (( failed_sched_count > 5 )); then
  sched_status="RED"
fi
echo "Eventos de scheduling con warning: $failed_sched_count"
echo "Semaforo scheduling: $sched_status"
echo ""
overall="$(max_severity "$overall" "$sched_status")"
echo "$RUN_TS,scheduling_status,$sched_status,failed_scheduling_events=$failed_sched_count" >> "$SUMMARY_CSV"

echo "[5/5] Resumen final"
echo "Runtime:          $runtime_status"
echo "Requests/Limits:  $requests_limits_status"
echo "Pending pods:     $pending_status"
echo "Scheduling:       $sched_status"
echo "-----------------------------------------------"
echo "SEMAFORO GLOBAL:  $overall"
echo ""
echo "$RUN_TS,overall,$overall,na" >> "$SUMMARY_CSV"

case "$overall" in
  GREEN)
    echo "Conclusion: capacidad adecuada para desplegar mas conectores (riesgo bajo)."
    ;;
  YELLOW)
    echo "Conclusion: se puede desplegar con cautela; revisar nodos/requests antes de escalar mucho."
    ;;
  RED)
    echo "Conclusion: no recomendado desplegar mas conectores sin ajustar recursos o escalar cluster."
    ;;
esac

echo ""
echo "==============================================="
echo "Detalle adicional (diagnostico ampliado)"
echo "==============================================="

echo "[A] CPU libre por nodo segun requests"
printf '%-38s %-12s %-12s %-12s %-8s\n' "NODE" "ALLOC_CPU(m)" "REQ_CPU(m)" "FREE_CPU(m)" "SEMAFORO"

cluster_free_cpu_m=0
free_cpu_status="GREEN"

while IFS= read -r node; do
  alloc_cpu_raw="$(kubectl get node "$node" -o jsonpath='{.status.allocatable.cpu}')"
  alloc_cpu_m="$(cpu_to_m "$alloc_cpu_raw")"

  desc="$(kubectl describe node "$node")"
  cpu_line="$(awk '/Allocated resources:/{flag=1;next}/Events:/{flag=0}flag && $1=="cpu"{print;exit}' <<< "$desc")"

  req_cpu_raw="$(awk '{print $2}' <<< "$cpu_line")"
  req_cpu_m="$(cpu_str_to_m "$req_cpu_raw")"

  free_cpu_m=$((alloc_cpu_m - req_cpu_m))
  if (( free_cpu_m < 0 )); then
    free_cpu_m=0
  fi

  node_sev="GREEN"
  if (( free_cpu_m <= FREE_CPU_RED_M )); then
    node_sev="RED"
  elif (( free_cpu_m <= FREE_CPU_YELLOW_M )); then
    node_sev="YELLOW"
  fi

  free_cpu_status="$(max_severity "$free_cpu_status" "$node_sev")"
  cluster_free_cpu_m=$((cluster_free_cpu_m + free_cpu_m))

  printf '%-38s %-12s %-12s %-12s %-8s\n' "$node" "$alloc_cpu_m" "$req_cpu_m" "$free_cpu_m" "$node_sev"
  echo "$RUN_TS,$node,$alloc_cpu_m,$req_cpu_m,$free_cpu_m,$node_sev" >> "$FREE_CPU_CSV"
done < <(kubectl get nodes -o name | sed 's|node/||')

echo "CPU libre total cluster (requests): ${cluster_free_cpu_m}m"
echo "Semaforo CPU libre: $free_cpu_status"
echo ""
echo "$RUN_TS,free_cpu_status,$free_cpu_status,cluster_free_cpu_m=$cluster_free_cpu_m" >> "$SUMMARY_CSV"

echo "[B] Top consumidores de CPU requests (pods)"
if command -v jq >/dev/null 2>&1; then
  top_req_file="$(mktemp)"
  kubectl get pods -A -o json | jq -r '
    .items[] as $p |
    (($p.spec.containers // []) | map(.resources.requests.cpu // "0")) as $cpus |
    [
      $p.metadata.namespace,
      $p.metadata.name,
      (
        $cpus | map(
          if test("m$") then (sub("m$"; "") | tonumber)
          elif . == "0" then 0
          else (tonumber * 1000)
          end
        ) | add
      )
    ] | @tsv' \
    | sort -k3,3nr \
    | head -n 20 > "$top_req_file"

  awk 'BEGIN{printf "%-18s %-55s %12s\n","NAMESPACE","POD","CPU_REQ(m)"} {printf "%-18s %-55s %12s\n",$1,$2,$3}' "$top_req_file"
  while IFS=$'\t' read -r ns pod cpu_req_m; do
    [[ -z "${ns:-}" ]] && continue
    echo "$RUN_TS,$ns,$pod,$cpu_req_m" >> "$TOP_REQ_CSV"
  done < "$top_req_file"
  rm -f "$top_req_file"
else
  echo "jq no disponible: no se puede generar ranking detallado de requests por pod."
fi
echo ""

echo "[C] Candidatos de ajuste (request alto con uso bajo)"
if command -v jq >/dev/null 2>&1; then
  declare -A CPU_USAGE_M
  while read -r ns pod cpu _mem; do
    [[ -z "${ns:-}" || -z "${pod:-}" || -z "${cpu:-}" ]] && continue
    usage_m="$(cpu_str_to_m "$cpu")"
    CPU_USAGE_M["$ns/$pod"]="$usage_m"
  done < <(kubectl top pods -A --no-headers 2>/dev/null || true)

  candidates_file="$(mktemp)"
  kubectl get pods -A -o json | jq -r '
    .items[] as $p |
    (($p.spec.containers // []) | map(.resources.requests.cpu // "0")) as $cpus |
    [
      $p.metadata.namespace,
      $p.metadata.name,
      (
        $cpus | map(
          if test("m$") then (sub("m$"; "") | tonumber)
          elif . == "0" then 0
          else (tonumber * 1000)
          end
        ) | add
      )
    ] | @tsv' | while IFS=$'\t' read -r ns pod req_m; do
      key="$ns/$pod"
      usage_m="${CPU_USAGE_M[$key]:-0}"
      (( req_m < MIN_REQUEST_CPU_M )) && continue
      (( req_m == 0 )) && continue
      usage_pct=$(( usage_m * 100 / req_m ))
      if (( usage_pct <= LOW_UTILIZATION_PCT )); then
        printf "%s\t%s\t%s\t%s\t%s\n" "$req_m" "$usage_m" "$usage_pct" "$ns" "$pod" >> "$candidates_file"
      fi
    done

  if [[ -s "$candidates_file" ]]; then
    sort -k1,1nr "$candidates_file" | head -n 20 | awk -F'\t' 'BEGIN{printf "%-18s %-55s %12s %12s %10s\n","NAMESPACE","POD","REQ(m)","USE(m)","USE%/REQ"} {printf "%-18s %-55s %12s %12s %9s%%\n",$4,$5,$1,$2,$3}'
    while IFS=$'\t' read -r req_m use_m use_pct ns pod; do
      [[ -z "${ns:-}" ]] && continue
      echo "$RUN_TS,$ns,$pod,$req_m,$use_m,$use_pct" >> "$CANDIDATES_CSV"
    done < <(sort -k1,1nr "$candidates_file" | head -n 20)
    echo "Sugerencia: revisar estos deployments/statefulsets y bajar request CPU gradualmente."
  else
    echo "No se detectaron candidatos claros con uso <= ${LOW_UTILIZATION_PCT}% del request."
  fi
  rm -f "$candidates_file"
else
  echo "jq no disponible: no se pueden calcular candidatos automaticamente."
fi
echo ""

echo "[D] Estimacion de conectores EDC adicionales por CPU request"
if command -v jq >/dev/null 2>&1; then
  ikln_req_m="$(kubectl get pods -n umbrella -o json | jq -r '
    [ .items[]
      | select(.metadata.name | startswith("ikln-edc-"))
      | (.spec.containers // [])
      | map(.resources.requests.cpu // "0")
      | map(if test("m$") then (sub("m$"; "") | tonumber) elif . == "0" then 0 else (tonumber * 1000) end)
      | add
    ] | add // 0')"
  mass_req_m="$(kubectl get pods -n umbrella -o json | jq -r '
    [ .items[]
      | select(.metadata.name | startswith("mass-edc-"))
      | (.spec.containers // [])
      | map(.resources.requests.cpu // "0")
      | map(if test("m$") then (sub("m$"; "") | tonumber) elif . == "0" then 0 else (tonumber * 1000) end)
      | add
    ] | add // 0')"

  connector_profile_m="$ikln_req_m"
  if (( mass_req_m > connector_profile_m )); then
    connector_profile_m="$mass_req_m"
  fi

  echo "CPU request perfil IKLN actual: ${ikln_req_m}m"
  echo "CPU request perfil MASS actual: ${mass_req_m}m"
  echo "CPU request perfil usado para estimacion (max): ${connector_profile_m}m"

  if (( connector_profile_m > 0 )); then
    estimated_additional=$(( cluster_free_cpu_m / connector_profile_m ))
    connector_semaphore="RED"
    echo "Conectores adicionales estimados (CPU requests): ${estimated_additional}"
    if (( estimated_additional >= 2 )); then
      echo "Semaforo estimacion conectores: GREEN"
      connector_semaphore="GREEN"
    elif (( estimated_additional == 1 )); then
      echo "Semaforo estimacion conectores: YELLOW"
      connector_semaphore="YELLOW"
    else
      echo "Semaforo estimacion conectores: RED"
      connector_semaphore="RED"
    fi
    echo "$RUN_TS,$ikln_req_m,$mass_req_m,$connector_profile_m,$cluster_free_cpu_m,$estimated_additional,$connector_semaphore" >> "$CONNECTOR_CSV"
    echo "$RUN_TS,connector_estimation,$connector_semaphore,estimated_additional=$estimated_additional" >> "$SUMMARY_CSV"
  else
    echo "No se pudo estimar conectores: no se detectaron pods ikln/mass para perfil base."
    echo "$RUN_TS,$ikln_req_m,$mass_req_m,$connector_profile_m,$cluster_free_cpu_m,0,UNKNOWN" >> "$CONNECTOR_CSV"
    echo "$RUN_TS,connector_estimation,UNKNOWN,no_profile_detected" >> "$SUMMARY_CSV"
  fi
else
  echo "jq no disponible: no se puede estimar conectores automaticamente."
  echo "$RUN_TS,connector_estimation,UNKNOWN,jq_not_available" >> "$SUMMARY_CSV"
fi

echo ""
echo "CSV generados en: $OUTPUT_DIR"
echo "  - $(basename "$SUMMARY_CSV")"
echo "  - $(basename "$RUNTIME_CSV")"
echo "  - $(basename "$REQUESTS_CSV")"
echo "  - $(basename "$FREE_CPU_CSV")"
echo "  - $(basename "$TOP_REQ_CSV")"
echo "  - $(basename "$CANDIDATES_CSV")"
echo "  - $(basename "$CONNECTOR_CSV")"

