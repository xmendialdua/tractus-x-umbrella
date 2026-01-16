#!/bin/bash
# Script to generate values-hosts.yaml from template using environment variables
# 
# Required environment variables:
#   LB_IP       - LoadBalancer IP address
#   DNS_SUFFIX  - DNS suffix (e.g., nip.io, catena-x.net)
#
# Usage:
#   export LB_IP="51.75.198.189"
#   export DNS_SUFFIX="nip.io"
#   ./generate_values_hosts_file_from_template.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/values-hosts-template.yaml"
OUTPUT_FILE="$SCRIPT_DIR/values-hosts.yaml"

# Validate required environment variables
if [ -z "$LB_IP" ]; then
    echo "Error: LB_IP environment variable is required"
    echo "Usage: export LB_IP=\"51.75.198.189\" && export DNS_SUFFIX=\"nip.io\" && $0"
    exit 1
fi

if [ -z "$DNS_SUFFIX" ]; then
    echo "Error: DNS_SUFFIX environment variable is required"
    echo "Usage: export LB_IP=\"51.75.198.189\" && export DNS_SUFFIX=\"nip.io\" && $0"
    exit 1
fi

# Validate template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Generate the values file
export OVH_LB_IP="$LB_IP"

if command -v envsubst &> /dev/null; then
    envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE"
else
    # Fallback to sed if envsubst is not available
    sed -e "s/\${OVH_LB_IP}/$LB_IP/g" -e "s/\${DNS_SUFFIX}/$DNS_SUFFIX/g" "$TEMPLATE_FILE" > "$OUTPUT_FILE"
fi

echo "✓ Generated: $OUTPUT_FILE"
echo "  LB_IP: $LB_IP"
echo "  DNS_SUFFIX: $DNS_SUFFIX"
