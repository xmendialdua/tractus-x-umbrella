#!/bin/bash

###############################################################
# Script to generate values-ovh-custom-domain.yaml from template
# This script replaces placeholders with actual values for:
# - Load Balancer IP
# - DNS suffix (typically IP.npi.io)
###############################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print usage
usage() {
    echo -e "${YELLOW}Usage:${NC}"
    echo "  $0 <LOAD_BALANCER_IP> [DNS_SUFFIX]"
    echo ""
    echo -e "${YELLOW}Arguments:${NC}"
    echo "  LOAD_BALANCER_IP    The IP address of the Load Balancer (required)"
    echo "  DNS_SUFFIX          The DNS suffix to use (optional, default: npi.io)"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  $0 83.44.55.66"
    echo "    -> Creates hostnames like: centralidp.83.44.55.66.npi.io"
    echo ""
    echo "  $0 83.44.55.66 npi.io"
    echo "    -> Creates hostnames like: centralidp.83.44.55.66.npi.io"
    echo ""
    echo "  $0 192.168.1.100 custom-domain.com"
    echo "    -> Creates hostnames like: centralidp.192.168.1.100.custom-domain.com"
    exit 1
}

# Function to print error message
error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

# Function to print success message
success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Function to print info message
info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Check if at least one argument is provided
if [ $# -lt 1 ]; then
    error "Missing required argument: LOAD_BALANCER_IP"
    usage
fi

# Get the Load Balancer IP
LOAD_BALANCER_IP="$1"

# Validate IP address format (basic validation)
if ! [[ "$LOAD_BALANCER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    error "Invalid IP address format: $LOAD_BALANCER_IP"
fi

# Get DNS suffix or use default
if [ $# -ge 2 ]; then
    DNS_SUFFIX="$2"
else
    DNS_SUFFIX="npi.io"
    info "No DNS_SUFFIX provided, using default: $DNS_SUFFIX"
fi

# Define paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/values-ovh-custom-domain.yaml.template"
OUTPUT_FILE="${SCRIPT_DIR}/values-ovh-custom-domain.yaml"

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    error "Template file not found: $TEMPLATE_FILE"
fi

info "Generating values file from template..."
info "  Load Balancer IP: $LOAD_BALANCER_IP"
info "  DNS Suffix: $DNS_SUFFIX"
info "  Full domain example: centralidp.${LOAD_BALANCER_IP}.${DNS_SUFFIX}"
info "  Template: $TEMPLATE_FILE"
info "  Output: $OUTPUT_FILE"

# Generate the values file by replacing placeholders
sed -e "s|__LOAD_BALANCER_IP__|${LOAD_BALANCER_IP}|g" \
    -e "s|__DNS_SUFFIX__|${DNS_SUFFIX}|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# Verify the output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    error "Failed to generate output file: $OUTPUT_FILE"
fi

success "Generated $OUTPUT_FILE"
echo ""
info "You can now use this file with helm install/upgrade:"
echo "  helm upgrade --install umbrella charts/umbrella -f charts/umbrella/values-ovh-custom-domain.yaml"
