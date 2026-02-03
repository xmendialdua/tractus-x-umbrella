#!/bin/bash

###############################################################################
# Fix Central IDP Redirect URIs in Partner Realms
###############################################################################
# Este script corrige los redirect URIs del cliente 'central-idp' en los
# realms de partners (idp1, idp2, etc.) para que coincidan con el nombre
# del identity provider broker correcto.
#
# Problema: El realm-seeding crea el cliente con redirect URI para
# CX-Operator, pero el broker real se llama igual que el realm (idp1, idp2).
#
# Solución: Actualizar redirectUris para incluir:
#   http://centralidp.{domain}/auth/realms/CX-Central/broker/{realm}/endpoint
#
# Uso: ./fix-centralidp-redirect-uri.sh [realm]
#      Si no se especifica realm, procesa todos los realms idp*
###############################################################################

set -e

NAMESPACE="portal"
POD="portal-sharedidp-0"
ADMIN_PASSWORD="adminconsolepwsharedidp"
DOMAIN="51.178.94.25.nip.io"
CONFIG_FILE="/tmp/kcadm.config"

REALM_PATTERN="${1:-idp*}"

echo "=========================================="
echo "Fix Central IDP Redirect URIs"
echo "=========================================="
echo "Namespace: $NAMESPACE"
echo "Domain: $DOMAIN"
echo "Realm Pattern: $REALM_PATTERN"
echo ""

# Función para autenticar en Keycloak
authenticate() {
    kubectl exec -n "$NAMESPACE" "$POD" -- bash -c \
        "cd /tmp && /opt/bitnami/keycloak/bin/kcadm.sh config credentials \
        --server http://localhost:8080/auth \
        --realm master \
        --user admin \
        --password $ADMIN_PASSWORD \
        --config $CONFIG_FILE" > /dev/null 2>&1
}

# Función para obtener lista de realms
get_realms() {
    if [ "$REALM_PATTERN" = "idp*" ]; then
        kubectl exec -n "$NAMESPACE" "$POD" -- bash -c \
            "cd /tmp && /opt/bitnami/keycloak/bin/kcadm.sh get realms \
            --config $CONFIG_FILE \
            --fields realm 2>/dev/null" | \
            grep '"realm"' | \
            awk -F'"' '{print $4}' | \
            grep -E "^idp[0-9]+$"
    else
        echo "$REALM_PATTERN"
    fi
}

# Función para actualizar redirect URIs
fix_redirect_uris() {
    local realm=$1
    local correct_uri="http://centralidp.$DOMAIN/auth/realms/CX-Central/broker/$realm/endpoint/*"
    
    echo "📝 Procesando realm: $realm"
    
    # Obtener el cliente central-idp
    local client_data=$(kubectl exec -n "$NAMESPACE" "$POD" -- bash -c \
        "cd /tmp && /opt/bitnami/keycloak/bin/kcadm.sh get clients \
        -r $realm \
        --config $CONFIG_FILE \
        -q clientId=central-idp 2>/dev/null")
    
    local client_id=$(echo "$client_data" | grep '"id"' | head -1 | awk -F'"' '{print $4}')
    
    if [ -z "$client_id" ]; then
        echo "   ⚠️  Cliente 'central-idp' no encontrado en realm $realm"
        return
    fi
    
    # Obtener redirectUris actuales
    local current_uris=$(echo "$client_data" | \
        sed -n '/"redirectUris"/,/\]/p' | \
        grep -o '"http[^"]*"' | \
        tr -d '"')
    
    echo "   URIs actuales:"
    if [ -z "$current_uris" ]; then
        echo "      (vacío)"
    else
        echo "$current_uris" | sed 's/^/      - /'
    fi
    
    # Verificar si ya existe el URI correcto
    if echo "$current_uris" | grep -q "$correct_uri"; then
        echo "   ✅ URI correcto ya existe"
        return
    fi
    
    # Establecer el URI correcto con wildcard
    echo "   Estableciendo URI: $correct_uri"
    
    # Actualizar el cliente con el URI correcto
    kubectl exec -n "$NAMESPACE" "$POD" -- bash -c \
        "cd /tmp && /opt/bitnami/keycloak/bin/kcadm.sh update clients/$client_id \
        -r $realm \
        --config $CONFIG_FILE \
        -s 'redirectUris=[\"$correct_uri\"]' 2>/dev/null"
    
    if [ $? -eq 0 ]; then
        echo "   ✅ Redirect URI actualizado correctamente"
    else
        echo "   ❌ Error al actualizar redirect URI"
    fi
}

# Autenticar
echo "Autenticando en Keycloak..."
authenticate
echo "✅ Autenticado"
echo ""

# Obtener lista de realms
echo "Buscando realms..."
realms=$(get_realms)

if [ -z "$realms" ]; then
    echo "❌ No se encontraron realms que coincidan con el patrón: $REALM_PATTERN"
    exit 1
fi

echo "Realms encontrados:"
echo "$realms" | sed 's/^/  - /'
echo ""

# Procesar cada realm
while IFS= read -r realm; do
    if [ -n "$realm" ]; then
        fix_redirect_uris "$realm"
        echo ""
    fi
done <<< "$realms"

echo "=========================================="
echo "Proceso completado"
echo "=========================================="
echo ""
echo "Verifica el acceso en:"
echo "http://portal.$DOMAIN"
echo ""
echo "Selecciona una compañía y verifica que no hay"
echo "errores de 'Invalid parameter: redirect_uri'"
echo "=========================================="
