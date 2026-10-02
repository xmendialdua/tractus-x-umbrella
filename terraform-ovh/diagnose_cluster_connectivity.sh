#!/bin/bash

echo "=== Kubernetes Cluster Connectivity Diagnostics ==="
echo ""

CLUSTER_URL="mu6hy9.c1.gra.k8s.ovh.net"

echo "1. DNS Resolution:"
nslookup $CLUSTER_URL || echo "DNS resolution failed"
echo ""

echo "2. Ping test:"
ping -c 3 $CLUSTER_URL || echo "Ping failed"
echo ""

echo "3. TCP connectivity to port 443:"
timeout 5 bash -c "echo > /dev/tcp/$CLUSTER_URL/443" && echo "✓ Port 443 is reachable" || echo "✗ Port 443 is NOT reachable"
echo ""

echo "4. HTTPS connectivity:"
curl -k -v --connect-timeout 10 https://$CLUSTER_URL:443 2>&1 | grep -E "Connected|SSL|TLS|timeout" || echo "HTTPS connection failed"
echo ""

echo "5. Current network route:"
ip route get 1.1.1.1 | head -1
echo ""

echo "6. Checking for proxy settings:"
echo "HTTP_PROXY: ${HTTP_PROXY:-not set}"
echo "HTTPS_PROXY: ${HTTPS_PROXY:-not set}"
echo "NO_PROXY: ${NO_PROXY:-not set}"
echo ""

echo "=== Diagnosis complete ==="
