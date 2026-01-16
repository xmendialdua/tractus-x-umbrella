#!/bin/bash
# Script to get LoadBalancer IP from Kubernetes cluster
# Returns the LoadBalancer IP address or exits with error
#
# Usage:
#   LB_IP=$(./get_loadbalancer_ip.sh)
#   echo "LoadBalancer IP: $LB_IP"

set -e

# Try to find the LoadBalancer IP from ingress-nginx namespace
# First, try to find any service with "ingress-nginx" in the name in the ingress-nginx namespace
LB_IP=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

# If not found, try to search in all namespaces for any LoadBalancer with ingress in the name
if [ -z "$LB_IP" ]; then
    LB_IP=$(kubectl get svc -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.type=="LoadBalancer" and (.metadata.name | contains("ingress"))) | .status.loadBalancer.ingress[0].ip' 2>/dev/null | head -n1 || echo "")
fi

if [ -z "$LB_IP" ]; then
    echo "Error: Could not detect LoadBalancer IP automatically" >&2
    echo "Available LoadBalancer services:" >&2
    kubectl get svc -A | grep LoadBalancer >&2 || echo "  No LoadBalancer services found" >&2
    echo "" >&2
    echo "Please ensure:" >&2
    echo "  1. kubectl is configured correctly" >&2
    echo "  2. ingress-nginx is deployed" >&2
    echo "  3. LoadBalancer has an external IP assigned" >&2
    exit 1
fi

# Output only the IP (for script consumption)
echo "$LB_IP"
