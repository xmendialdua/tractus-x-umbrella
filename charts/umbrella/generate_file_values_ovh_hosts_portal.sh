#!/bin/bash
# #############################################################################
# Copyright (c) 2024 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Apache License, Version 2.0 which is available at
# https://www.apache.org/licenses/LICENSE-2.0.
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.
#
# SPDX-License-Identifier: Apache-2.0
# #############################################################################

# Script to generate Portal values file from template
# Usage: ./generate_portal_values.sh <LOAD_BALANCER_IP> [DNS_SUFFIX]
# Example: ./generate_portal_values.sh 51.83.104.91 .npi.io
# Example: ./generate_portal_values.sh 51.83.104.91

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required argument is provided
if [ $# -lt 1 ]; then
    print_error "Missing required argument: LOAD_BALANCER_IP"
    echo ""
    echo "Usage: $0 <LOAD_BALANCER_IP> [DNS_SUFFIX]"
    echo ""
    echo "Arguments:"
    echo "  LOAD_BALANCER_IP  The load balancer IP address (e.g., 51.83.104.91)"
    echo "  DNS_SUFFIX        Optional DNS suffix (default: \"\", example: \".npi.io\")"
    echo ""
    echo "Examples:"
    echo "  $0 51.83.104.91"
    echo "  $0 51.83.104.91 .npi.io"
    exit 1
fi

# Get arguments
LOAD_BALANCER_IP="$1"
DNS_SUFFIX="${2:-}"  # Default to empty string if not provided

# Validate IP address format (basic validation)
if ! [[ "$LOAD_BALANCER_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    print_error "Invalid IP address format: $LOAD_BALANCER_IP"
    exit 1
fi

# Set file paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/values-ovh-hosts-portal-template.yaml"
OUTPUT_FILE="$SCRIPT_DIR/values-ovh-hosts-portal.yaml"

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_error "Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Print configuration
print_info "Configuration:"
echo "  Load Balancer IP: $LOAD_BALANCER_IP"
if [ -z "$DNS_SUFFIX" ]; then
    echo "  DNS Suffix: <none>"
    echo "  Final domain format: <subdomain>.$LOAD_BALANCER_IP.nip.io"
else
    echo "  DNS Suffix: $DNS_SUFFIX"
    echo "  Final domain format: <subdomain>.$LOAD_BALANCER_IP$DNS_SUFFIX"
fi
echo "  Template: $TEMPLATE_FILE"
echo "  Output: $OUTPUT_FILE"
echo ""

# Confirm before proceeding
read -p "Do you want to proceed? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Operation cancelled by user"
    exit 0
fi

# Generate values file from template
print_info "Generating values file..."

# If DNS_SUFFIX is empty, use .nip.io as default
if [ -z "$DNS_SUFFIX" ]; then
    FULL_SUFFIX=".nip.io"
else
    FULL_SUFFIX="$DNS_SUFFIX"
fi

# Replace placeholders in template
sed -e "s|{{LOAD_BALANCER_IP}}|$LOAD_BALANCER_IP|g" \
    -e "s|{{DNS_SUFFIX}}|$FULL_SUFFIX|g" \
    "$TEMPLATE_FILE" > "$OUTPUT_FILE"

# Check if file was created successfully
if [ -f "$OUTPUT_FILE" ]; then
    print_info "Successfully generated values file: $OUTPUT_FILE"
    echo ""
    print_info "You can now deploy the portal using:"
    echo "  helm upgrade --install portal . \\"
    echo "    -f values-adopter-portal.yaml \\"
    echo "    -f $OUTPUT_FILE \\"
    echo "    -n portal --create-namespace"
    echo ""
    print_warning "Note: This configuration removes 'tx.test' references from Keycloak databases"
    print_warning "Make sure the load balancer IP is correctly configured before deployment"
else
    print_error "Failed to generate values file"
    exit 1
fi
