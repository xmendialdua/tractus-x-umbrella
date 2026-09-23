#!/bin/bash
# Collects kubectl info (pods/jobs/svc/deployments + extras) for a fixed set of namespaces.
# Produces, per query: a raw .txt (kubectl output) and a ';'-delimited .txt ready to paste into a Word table.
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml}"

NAMESPACES=(portal umbrella ds-management-ui cert-manager wallet edc-ui)

TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUTROOT="$(dirname "$0")/reports/cluster-info_${TIMESTAMP}"
mkdir -p "$OUTROOT"

# query_name -> kubectl args (namespace is injected with -n)
declare -A QUERIES=(
  [01_pods]="get pods -o wide"
  [02_jobs]="get jobs -o wide"
  [03_svc]="get svc -o wide"
  [04_deployments]="get deployments -o wide"
  [05_replicasets]="get replicasets -o wide"
  [06_statefulsets]="get statefulsets -o wide"
  [07_ingress]="get ingress -o wide"
  [08_pvc]="get pvc -o wide"
  [09_events]="get events --sort-by=.lastTimestamp"
  [10_top_pods]="top pods"
)

# Convert kubectl's whitespace-aligned tabular output into a ';'-delimited file (one field separator per column boundary).
to_semicolon_table() {
  sed -E 's/  +/;/g' "$1"
}

for ns in "${NAMESPACES[@]}"; do
  nsdir="$OUTROOT/$ns"
  mkdir -p "$nsdir"

  for qname in "${!QUERIES[@]}"; do
    args="${QUERIES[$qname]}"
    raw_file="$nsdir/${qname}.txt"
    table_file="$nsdir/${qname}_tabla.txt"

    # shellcheck disable=SC2086
    kubectl -n "$ns" $args > "$raw_file" 2>&1 || true

    to_semicolon_table "$raw_file" > "$table_file"
  done

  # Consolidated overview of all namespaced resources (handy extra, not split into a table version).
  kubectl -n "$ns" get all -o wide > "$nsdir/00_get-all.txt" 2>&1 || true
done

echo "Reports written to: $OUTROOT"
