#!/bin/bash

# Script para detectar cuándo se crea un nuevo realm durante el onboarding
# Uso: ./check-new-realm.sh [watch]
# Con 'watch' monitorea cada 10 segundos

KUBECONFIG_PATH="/home/xmendialdua/projects/assembly/tractus-x-umbrella/kubeconfig.yaml"
NAMESPACE="portal"
ADMIN_PASSWORD=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get secret portal-sharedidp -n "$NAMESPACE" -o jsonpath='{.data.admin-password}' | base64 -d)

get_realms() {
    SHAREDIDP_POD=$(kubectl --kubeconfig="$KUBECONFIG_PATH" get pods -n "$NAMESPACE" -l app.kubernetes.io/name=sharedidp -o jsonpath='{.items[0].metadata.name}')
    
    kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n "$NAMESPACE" "$SHAREDIDP_POD" -- /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
      --server http://localhost:8080/auth \
      --realm master \
      --user admin \
      --password "$ADMIN_PASSWORD" \
      --config /tmp/kcadm.config 2>/dev/null
    
    kubectl --kubeconfig="$KUBECONFIG_PATH" exec -n "$NAMESPACE" "$SHAREDIDP_POD" -- /opt/bitnami/keycloak/bin/kcadm.sh get realms \
      --config /tmp/kcadm.config --fields realm 2>/dev/null | jq -r '.[] | .realm'
}

check_for_new_realms() {
    echo "=== Realms actuales en Keycloak ($(date '+%Y-%m-%d %H:%M:%S')) ==="
    CURRENT_REALMS=$(get_realms)
    echo "$CURRENT_REALMS"
    echo ""
    
    # Filtrar solo los realms de partners (idp*)
    PARTNER_REALMS=$(echo "$CURRENT_REALMS" | grep "^idp" || true)
    if [ -n "$PARTNER_REALMS" ]; then
        echo "🎯 Realms de partners detectados:"
        echo "$PARTNER_REALMS"
        echo ""
        echo "⚠️  Recuerda ejecutar: ./fix-realm-https.sh <realm-name>"
        return 0
    else
        echo "ℹ️  Aún no hay realms de partners (idp*)"
        return 1
    fi
}

if [ "$1" = "watch" ]; then
    echo "🔍 Monitoreando creación de nuevos realms (Ctrl+C para detener)..."
    echo ""
    
    while true; do
        check_for_new_realms
        echo "---"
        sleep 10
    done
else
    check_for_new_realms
fi
