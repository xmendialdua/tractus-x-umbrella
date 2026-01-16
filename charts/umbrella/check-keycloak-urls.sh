#!/bin/bash
# Comandos para verificar URLs en las bases de datos de Keycloak
# Ejecutar ANTES de aplicar fix-keycloak-urls-job.yaml
#
# Este script ejecuta comandos SQL directamente en los pods de PostgreSQL existentes

# ============================================================================
# OBTENER NOMBRES DE LOS PODS DE POSTGRESQL
# ============================================================================

echo "=== OBTENIENDO PODS DE POSTGRESQL ==="
echo ""
echo "Buscando pods en el namespace portal..."
kubectl get pods -n portal | grep -i postgres

echo ""
echo "Intentando diferentes patrones de búsqueda..."

# Intentar diferentes patrones
CENTRAL_POD=$(kubectl get pod -n portal -l app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=portal-centralidp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$CENTRAL_POD" ]; then
    CENTRAL_POD=$(kubectl get pod -n portal -o name | grep -i "centralidp.*postgres" | head -1 | cut -d'/' -f2)
fi

SHARED_POD=$(kubectl get pod -n portal -l app.kubernetes.io/name=postgresql,app.kubernetes.io/instance=portal-sharedidp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$SHARED_POD" ]; then
    SHARED_POD=$(kubectl get pod -n portal -o name | grep -i "sharedidp.*postgres" | head -1 | cut -d'/' -f2)
fi

echo ""
echo "Central IDP pod: $CENTRAL_POD"
echo "Shared IDP pod: $SHARED_POD"
echo ""

if [ -z "$CENTRAL_POD" ] || [ -z "$SHARED_POD" ]; then
    echo "ERROR: No se pudieron encontrar los pods de PostgreSQL"
    echo ""
    echo "=== DIAGNÓSTICO ==="
    echo "Todos los pods en el namespace portal:"
    kubectl get pods -n portal
    echo ""
    echo "Para ejecutar manualmente, identifica los pods correctos y ejecuta:"
    echo "  kubectl exec -n portal <CENTRAL_POD> -- psql -U kccentral -d iamcentralidp -c 'SELECT * FROM client;'"
    exit 1
fi

# ============================================================================
# VERIFICACIÓN DE BASE DE DATOS: CENTRAL IDP (iamcentralidp)
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Verificar client.root_url - Portal principal
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "1. CENTRAL IDP - client.root_url"
echo "=========================================="

kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  SELECT 
    client_id, 
    root_url, 
    CASE 
      WHEN root_url LIKE '%tx.test%' THEN '⚠️  CONTIENE tx.test'
      ELSE '✓ OK'
    END as status
  FROM client 
  WHERE root_url IS NOT NULL
  ORDER BY client_id;
\""

# ----------------------------------------------------------------------------
# 2. Verificar redirect_uris - URLs de redirección de clientes
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "2. CENTRAL IDP - redirect_uris"
echo "=========================================="

kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  SELECT 
    c.client_id,
    r.value as redirect_uri,
    CASE 
      WHEN r.value LIKE '%tx.test%' THEN '⚠️  CONTIENE tx.test'
      ELSE '✓ OK'
    END as status
  FROM redirect_uris r
  JOIN client c ON r.client_id = c.id
  ORDER BY c.client_id, r.value;
\""

# ----------------------------------------------------------------------------
# 3. Verificar identity_provider_config - URLs del IDP (CX-Operator)
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "3. CENTRAL IDP - identity_provider_config"
echo "=========================================="

kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  SELECT 
    ip.provider_alias,
    ipc.name as config_key,
    ipc.value as config_value,
    CASE 
      WHEN ipc.value LIKE '%tx.test%' THEN '⚠️  CONTIENE tx.test'
      ELSE '✓ OK'
    END as status
  FROM identity_provider_config ipc
  JOIN identity_provider ip ON ipc.identity_provider_id = ip.internal_id
  WHERE ipc.name IN ('tokenUrl', 'authorizationUrl', 'jwksUrl', 'logoutUrl')
  ORDER BY ip.provider_alias, ipc.name;
\""

# ----------------------------------------------------------------------------
# 4. Búsqueda global en CENTRAL IDP - Todas las URLs con tx.test
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "4. CENTRAL IDP - Búsqueda global tx.test"
echo "=========================================="

kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  SELECT 'client.root_url' as tabla, client_id as identificador, root_url as url
  FROM client 
  WHERE root_url LIKE '%tx.test%'
  UNION ALL
  SELECT 'redirect_uris' as tabla, c.client_id as identificador, r.value as url
  FROM redirect_uris r
  JOIN client c ON r.client_id = c.id
  WHERE r.value LIKE '%tx.test%'
  UNION ALL
  SELECT 'identity_provider_config' as tabla, ip.provider_alias as identificador, ipc.value as url
  FROM identity_provider_config ipc
  JOIN identity_provider ip ON ipc.identity_provider_id = ip.internal_id
  WHERE ipc.value LIKE '%tx.test%';
\""


# ============================================================================
# VERIFICACIÓN DE BASE DE DATOS: SHARED IDP (iamsharedidp)
# ============================================================================

# ----------------------------------------------------------------------------
# 5. Verificar redirect_uris - URLs de redirección del cliente central-idp
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "5. SHARED IDP - redirect_uris"
echo "=========================================="

kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  SELECT 
    c.client_id,
    r.value as redirect_uri,
    CASE 
      WHEN r.value LIKE '%tx.test%' THEN '⚠️  CONTIENE tx.test'
      ELSE '✓ OK'
    END as status
  FROM redirect_uris r
  JOIN client c ON r.client_id = c.id
  ORDER BY c.client_id, r.value;
\""

# ----------------------------------------------------------------------------
# 6. Verificar client_attributes - jwks.url para validación de tokens
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "6. SHARED IDP - client_attributes (jwks.url)"
echo "=========================================="

kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  SELECT 
    c.client_id,
    ca.name as attribute_name,
    ca.value as attribute_value,
    CASE 
      WHEN ca.value LIKE '%tx.test%' THEN '⚠️  CONTIENE tx.test'
      ELSE '✓ OK'
    END as status
  FROM client_attributes ca
  JOIN client c ON ca.client_id = c.id
  WHERE ca.name = 'jwks.url'
  ORDER BY c.client_id;
\""

# ----------------------------------------------------------------------------
# 7. Búsqueda global en SHARED IDP - Todas las URLs con tx.test
# ----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "7. SHARED IDP - Búsqueda global tx.test"
echo "=========================================="

kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  SELECT 'redirect_uris' as tabla, c.client_id as identificador, r.value as url
  FROM redirect_uris r
  JOIN client c ON r.client_id = c.id
  WHERE r.value LIKE '%tx.test%'
  UNION ALL
  SELECT 'client_attributes' as tabla, c.client_id as identificador, ca.value as url
  FROM client_attributes ca
  JOIN client c ON ca.client_id = c.id
  WHERE ca.value LIKE '%tx.test%';
\""


# ============================================================================
# RESUMEN - Ver qué IP está actualmente configurada
# ============================================================================

echo ""
echo "=========================================="
echo "8. RESUMEN - IPs configuradas actualmente"
echo "=========================================="

echo ""
echo "--- En CENTRAL IDP ---"
kubectl exec -n portal $CENTRAL_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kccentral -d iamcentralidp -c \"
  SELECT DISTINCT 
    substring(value from 'http://[^/]+') as url_base
  FROM (
    SELECT root_url as value FROM client WHERE root_url IS NOT NULL
    UNION
    SELECT value FROM redirect_uris
    UNION
    SELECT value FROM identity_provider_config WHERE value LIKE 'http%'
  ) urls
  ORDER BY url_base;
\""

echo ""
echo "--- En SHARED IDP ---"
kubectl exec -n portal $SHARED_POD -- bash -c "PGPASSWORD=\$POSTGRES_PASSWORD psql -U kcshared -d iamsharedidp -c \"
  SELECT DISTINCT 
    substring(value from 'http://[^/]+') as url_base
  FROM (
    SELECT value FROM redirect_uris
    UNION
    SELECT value FROM client_attributes WHERE value LIKE 'http%'
  ) urls
  ORDER BY url_base;
\""

echo ""
echo "=========================================="
echo "VERIFICACIÓN COMPLETADA"
echo "=========================================="
echo ""
echo "Si encontraste URLs con ⚠️ CONTIENE tx.test:"
echo "1. Edita fix-keycloak-urls-job.yaml con la IP correcta"
echo "2. Ejecuta: kubectl apply -f fix-keycloak-urls-job.yaml -n portal"
echo "3. Verifica: kubectl logs -n portal job/fix-keycloak-urls -f"
echo "4. Reinicia: kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp"
echo "5. Reinicia: kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp"
echo ""
