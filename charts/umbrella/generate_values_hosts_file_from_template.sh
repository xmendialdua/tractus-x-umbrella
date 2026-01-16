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

echo "================================================"
echo "DEBUG: Script directory resolution"
echo "================================================"
echo "SCRIPT_DIR: $SCRIPT_DIR"
echo "TEMPLATE_FILE: $TEMPLATE_FILE"
echo "OUTPUT_FILE: $OUTPUT_FILE"
echo "Current directory (pwd): $(pwd)"
echo "================================================"
echo ""

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

echo "Generating values file..."
echo "  Template: $TEMPLATE_FILE"
echo "  Output: $OUTPUT_FILE"
echo "  LB_IP: $LB_IP"
echo "  DNS_SUFFIX: $DNS_SUFFIX"
echo ""

# Remove old output file if exists (to ensure we're generating fresh)
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing existing output file..."
    rm -f "$OUTPUT_FILE"
fi

# Try to generate the file
if command -v envsubst &> /dev/null; then
    echo "Using envsubst for generation..."
    if ! envsubst < "$TEMPLATE_FILE" > "$OUTPUT_FILE" 2>&1; then
        echo "Error: envsubst failed to generate the file" >&2
        exit 1
    fi
else
    echo "Using sed for generation (envsubst not available)..."
    if ! sed -e "s/\${OVH_LB_IP}/$LB_IP/g" -e "s/\${DNS_SUFFIX}/$DNS_SUFFIX/g" "$TEMPLATE_FILE" > "$OUTPUT_FILE" 2>&1; then
        echo "Error: sed failed to generate the file" >&2
        exit 1
    fi
fi

# Verify the file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file was not created: $OUTPUT_FILE" >&2
    echo "Possible causes:" >&2
    echo "  - No write permissions in directory: $SCRIPT_DIR" >&2
    echo "  - Disk full" >&2
    echo "  - File system is read-only" >&2
    ls -ld "$SCRIPT_DIR" >&2
    exit 1
fi

# Verify the file has content
FILE_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
if [ "$FILE_SIZE" -eq 0 ]; then
    echo "Error: Output file was created but is empty: $OUTPUT_FILE" >&2
    echo "Template file size: $(stat -f%z "$TEMPLATE_FILE" 2>/dev/null || stat -c%s "$TEMPLATE_FILE" 2>/dev/null || echo "unknown")" >&2
    exit 1
fi

# Verify the substitutions were made
if grep -q '\${OVH_LB_IP}' "$OUTPUT_FILE" || grep -q '\${DNS_SUFFIX}' "$OUTPUT_FILE"; then
    echo "Warning: Output file still contains placeholders. Substitution may have failed." >&2
    echo "First few lines of output:" >&2
    head -n 10 "$OUTPUT_FILE" >&2
fi

echo ""
echo "✓ Successfully generated: $OUTPUT_FILE"
echo "  File size: $FILE_SIZE bytes"
echo "  LB_IP replaced: $LB_IP"
echo "  DNS_SUFFIX replaced: $DNS_SUFFIX"
echo ""
echo "Verifying file location:"
echo "  Full path: $OUTPUT_FILE"
echo "  Exists: $([ -f "$OUTPUT_FILE" ] && echo "YES" || echo "NO")"
echo "  Readable: $([ -r "$OUTPUT_FILE" ] && echo "YES" || echo "NO")"
echo ""
echo "To verify, run from the script directory:"
echo "  cd $SCRIPT_DIR"
echo "  ls -la values-hosts.yaml"
