#!/bin/bash
# Script to fix Keycloak URLs in the database
# Ejecuta las correcciones SQL directamente en los pods de PostgreSQL existentes
#
# Usage:
#   export EXTERNAL_IP="51.83.104.91"
#   export DNS_SUFFIX="nip.io"
#   ./fix-keycloak-urls.sh

set -e

# ============================================================================
# VALIDAR VARIABLES DE ENTORNO
# ============================================================================

if [ -z "$EXTERNAL_IP" ]; then
    echo "ERROR: La variable EXTERNAL_IP no está configurada"
    echo "Uso: export EXTERNAL_IP=\"51.83.104.91\" && export DNS_SUFFIX=\"nip.io\" && ./fix-keycloak-urls.sh"
    exit 1
fi

if [ -z "$DNS_SUFFIX" ]; then
    echo "ERROR: La variable DNS_SUFFIX no está configurada"
    echo "Uso: export EXTERNAL_IP=\"51.83.104.91\" && export DNS_SUFFIX=\"nip.io\" && ./fix-keycloak-urls.sh"
    exit 1
fi

# ============================================================================
# OBTENER PODS DE POSTGRESQL
# ============================================================================

echo "=========================================="
echo "Keycloak URL Fix Script"
echo "=========================================="
echo "External IP: $EXTERNAL_IP"
echo "DNS Suffix: $DNS_SUFFIX"
echo ""

echo "Obteniendo pods de PostgreSQL..."
CENTRAL_POD=$(kubectl get pod -n portal -o name | grep -i "centralidp.*postgres" | head -1 | cut -d'/' -f2)
SHARED_POD=$(kubectl get pod -n portal -o name | grep -i "sharedidp.*postgres" | head -1 | cut -d'/' -f2)

if [ -z "$CENTRAL_POD" ] || [ -z "$SHARED_POD" ]; then
    echo "ERROR: No se encontraron los pods de PostgreSQL"
    echo "Central IDP pod: $CENTRAL_POD"
    echo "Shared IDP pod: $SHARED_POD"
    exit 1
fi

echo "Central IDP pod: $CENTRAL_POD"
echo "Shared IDP pod: $SHARED_POD"
echo ""

# ============================================================================
# FIXING CENTRAL IDP DATABASE
# ============================================================================

echo "=========================================="
echo "FIXING CENTRAL IDP DATABASE"
echo "=========================================="
echo ""

# 1. Fix client root_url for Cl2-CX-Portal
echo "1. Updating client.root_url for Cl2-CX-Portal..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE client 
  SET root_url = 'http://portal.$EXTERNAL_IP.$DNS_SUFFIX/home' 
  WHERE client_id = 'Cl2-CX-Portal';
\""
echo "   ✓ root_url updated"

# 2. Fix redirect_uris for PORTAL clients (Cl1, Cl2, Cl3)
echo "2. Updating redirect_uris for portal clients..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE redirect_uris 
  SET value = 'http://portal.$EXTERNAL_IP.$DNS_SUFFIX/*' 
  WHERE client_id IN (
    SELECT id FROM client WHERE client_id IN ('Cl1-CX-Registration', 'Cl2-CX-Portal', 'Cl3-CX-Semantic')
  );
\""
echo "   ✓ Portal redirect_uris updated"

# 3. Fix redirect_uris for BPDM Gate (Cl16)
echo "3. Updating redirect_uris for BPDM Gate..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE redirect_uris 
  SET value = 'http://partners-gate.$EXTERNAL_IP.$DNS_SUFFIX/*' 
  WHERE client_id IN (
    SELECT id FROM client WHERE client_id = 'Cl16-CX-BPDMGate'
  );
\""
echo "   ✓ BPDM Gate redirect_uri updated"

# 4. Fix redirect_uris for BPDM Pool (Cl7)
echo "4. Updating redirect_uris for BPDM Pool..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE redirect_uris 
  SET value = 'http://partners-pool.$EXTERNAL_IP.$DNS_SUFFIX/*' 
  WHERE client_id IN (
    SELECT id FROM client WHERE client_id = 'Cl7-CX-BPDM'
  );
\""
echo "   ✓ BPDM Pool redirect_uri updated"

# 5. Fix redirect_uris for Custodian/MIW (Cl5)
echo "5. Updating redirect_uris for Custodian..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE redirect_uris 
  SET value = 'http://managed-identity-wallets.$EXTERNAL_IP.$DNS_SUFFIX/*' 
  WHERE client_id IN (
    SELECT id FROM client WHERE client_id = 'Cl5-CX-Custodian'
  );
\""
echo "   ✓ Custodian redirect_uri updated"

# 6. Fix identity_provider_config URLs
echo "6. Updating identity_provider_config URLs for CX-Operator..."
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  UPDATE identity_provider_config 
  SET value = REPLACE(value, 'sharedidp.tx.test', 'sharedidp.$EXTERNAL_IP.$DNS_SUFFIX')
  WHERE identity_provider_id IN (
    SELECT internal_id FROM identity_provider WHERE provider_alias = 'CX-Operator'
  )
  AND name IN ('tokenUrl', 'authorizationUrl', 'jwksUrl', 'logoutUrl');
\""
echo "   ✓ Identity provider config URLs updated"

# ============================================================================
# FIXING SHARED IDP DATABASE
# ============================================================================

echo ""
echo "=========================================="
echo "FIXING SHARED IDP DATABASE"
echo "=========================================="
echo ""

# 7. Fix redirect_uri for central-idp client
echo "7. Updating redirect_uri for central-idp client..."
kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  UPDATE redirect_uris 
  SET value = 'http://centralidp.$EXTERNAL_IP.$DNS_SUFFIX/auth/realms/CX-Central/broker/CX-Operator/endpoint/*'
  WHERE client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');
\""
echo "   ✓ redirect_uri updated"

# 8. Fix jwks.url in client_attributes
echo "8. Updating client_attributes.jwks.url for central-idp..."
kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  UPDATE client_attributes 
  SET value = 'http://centralidp.$EXTERNAL_IP.$DNS_SUFFIX/auth/realms/CX-Central/protocol/openid-connect/certs'
  WHERE name = 'jwks.url' 
  AND client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');
\""
echo "   ✓ jwks.url updated"

# ============================================================================
# COMPLETADO
# ============================================================================

echo ""
echo "=========================================="
echo "Keycloak URL Fix Completed Successfully"
echo "=========================================="
echo ""
echo "URLs actualizadas:"
echo "  - Portal: http://portal.$EXTERNAL_IP.$DNS_SUFFIX"
echo "  - BPDM Gate: http://partners-gate.$EXTERNAL_IP.$DNS_SUFFIX"
echo "  - BPDM Pool: http://partners-pool.$EXTERNAL_IP.$DNS_SUFFIX"
echo "  - Custodian: http://managed-identity-wallets.$EXTERNAL_IP.$DNS_SUFFIX"
echo "  - Central IDP: http://centralidp.$EXTERNAL_IP.$DNS_SUFFIX"
echo "  - Shared IDP: http://sharedidp.$EXTERNAL_IP.$DNS_SUFFIX"
echo ""
echo "NEXT STEPS:"
echo "1. Restart centralidp pods:"
echo "   kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp"
echo ""
echo "2. Restart sharedidp pods:"
echo "   kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp"
echo ""
echo "3. Wait for pods to be ready (2-3 minutes)"
echo "   kubectl get pods -n portal -w"
echo ""
echo "4. Test login at:"
echo "   http://portal.$EXTERNAL_IP.$DNS_SUFFIX"
echo ""
echo "5. Verify URLs were updated:"
echo "   ./check-keycloak-urls.sh"
echo "=========================================="
