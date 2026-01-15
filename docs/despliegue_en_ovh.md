# Despliegue del Portal Tractus-X en OVH Kubernetes

## Requisitos Previos

- Cluster Kubernetes en OVH (versión >= 1.24)
- kubectl configurado con acceso al cluster
- Helm 3 instalado
- Kubeconfig del cluster de OVH

## Arquitectura del Despliegue

El despliegue incluye:
- **Portal Frontend y Backend**: Interfaz de usuario y APIs
- **Central IDP**: Keycloak para autenticación de usuarios del portal
- **Shared IDP**: Keycloak para federación de identidades entre organizaciones
- **PostgreSQL**: Bases de datos para cada Keycloak (sin persistencia)
- **Nginx Ingress Controller**: Balanceador de carga con IP externa de OVH
- **pgAdmin4**: Herramienta de administración de bases de datos

## Paso 1: Configurar kubeconfig

```bash
export KUBECONFIG=/ruta/al/kubeconfig-xxxxx.yml
kubectl get nodes
```

## Paso 2: Instalar Nginx Ingress Controller

```bash
# Añadir repositorio de Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# Instalar Nginx Ingress Controller con LoadBalancer de OVH
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer

# Esperar a que se asigne IP externa
kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -w
```

**Anotar la EXTERNAL-IP asignada** (por ejemplo: 51.75.198.189)

## Paso 3: Preparar Repositorio de Helm

```bash
cd /ruta/a/tractus-x-umbrella/charts/umbrella

# Añadir repositorios necesarios
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add tractusx-dev https://eclipse-tractusx.github.io/charts/dev
helm repo update

# Actualizar dependencias
helm dependency update
```

## Paso 4: Crear Namespace

```bash
kubectl create namespace portal
```

## Paso 5: Configurar values-ovh-hosts.yaml

El archivo `values-ovh-hosts.yaml` debe contener las URLs correctas usando la IP externa:

```yaml
# Reemplazar 51.75.198.189 con tu IP externa de OVH
portal:
  portalAddress: "http://portal.51.75.198.189.nip.io"
  portalBackendAddress: "http://portal-backend.51.75.198.189.nip.io"
  centralidp:
    address: "http://centralidp.51.75.198.189.nip.io"
  sharedidpAddress: "http://sharedidp.51.75.198.189.nip.io"
  # ... (resto de configuración)

centralidp:
  keycloak:
    ingress:
      enabled: true
      ingressClassName: "nginx"
      hostname: "centralidp.51.75.198.189.nip.io"
      tls: false
    extraEnvVars:
      - name: KEYCLOAK_FRONTEND_URL
        value: "http://centralidp.51.75.198.189.nip.io/auth/"
      - name: KC_HTTP_ENABLED
        value: "true"
      - name: KEYCLOAK_PRODUCTION
        value: "false"
    realmSeeding:
      clients:
        portal:
          rootUrl: http://portal.51.75.198.189.nip.io/home
          redirects:
            - http://portal.51.75.198.189.nip.io/*
      sharedidp: "http://sharedidp.51.75.198.189.nip.io"

sharedidp:
  keycloak:
    ingress:
      enabled: true
      ingressClassName: "nginx"
      hostname: "sharedidp.51.75.198.189.nip.io"
      tls: false
    extraEnvVars:
      - name: KEYCLOAK_FRONTEND_URL
        value: "http://sharedidp.51.75.198.189.nip.io/auth/"
      - name: KC_HTTP_ENABLED
        value: "true"
      - name: KEYCLOAK_PRODUCTION
        value: "false"
    realmSeeding:
      realms:
        cxOperator:
          centralidp: "http://centralidp.51.75.198.189.nip.io"
```

## Paso 6: Desplegar el Portal

```bash
helm install portal . \
  -f values-adopter-portal.yaml \
  -f values-ovh-hosts.yaml \
  -n portal

# Monitorear el despliegue
kubectl get pods -n portal -w
```

## Paso 7: Corrección de URLs en Bases de Datos

**⚠️ IMPORTANTE**: Debido a que el realm seeding de Keycloak es idempotente (solo crea datos, no los actualiza), algunas URLs quedan con valores por defecto `.tx.test` que deben corregirse manualmente.

### Problema: URLs no actualizadas

El realm seeding NO actualiza:
- URLs de clientes ya existentes en Central IDP
- URLs del identity provider en Central IDP
- URLs de clientes en Shared IDP

### Bases de Datos Afectadas

1. **iamcentralidp** (Central IDP)
   - Usuario: `kccentral`
   - Tablas: `client`, `redirect_uris`, `identity_provider_config`

2. **iamsharedidp** (Shared IDP)
   - Usuario: `kcshared`
   - Tablas: `redirect_uris`, `client_attributes`

### Solución Automática: Ejecutar Job de Corrección

```bash
# Aplicar el Job que corrige las URLs automáticamente
kubectl apply -f fix-keycloak-urls-job.yaml -n portal

# Verificar ejecución del Job
kubectl logs -n portal job/fix-keycloak-urls -f

# El Job realiza las siguientes correcciones:
# 1. client.root_url en centralidp
# 2. redirect_uris en centralidp (3 clientes)
# 3. identity_provider_config en centralidp (4 URLs)
# 4. redirect_uris en sharedidp
# 5. client_attributes.jwks.url en sharedidp

# Una vez completado, reiniciar pods de Keycloak
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
```

### Solución Manual (Alternativa)

Si prefieres hacer las correcciones manualmente:

#### 7.1 Obtener Passwords de Bases de Datos

```bash
# Password de Central IDP
export PGPASSWORD_CENTRAL=$(kubectl get secret -n portal portal-centralidp-postgresql \
  -o jsonpath='{.data.password}' | base64 -d)

# Password de Shared IDP
export PGPASSWORD_SHARED=$(kubectl get secret -n portal portal-sharedidp-postgresql \
  -o jsonpath='{.data.password}' | base64 -d)
```

#### 7.2 Corregir Central IDP Database

**Razón**: Los clientes del portal tienen redirect_uris y root_url apuntando a `portal.tx.test` en lugar de la IP de OVH.

```bash
# 1. Actualizar root_url del cliente Cl2-CX-Portal
kubectl exec -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL psql -U kccentral -d iamcentralidp -c \
  "UPDATE client SET root_url = 'http://portal.51.75.198.189.nip.io/home' 
   WHERE client_id = 'Cl2-CX-Portal';"

# 2. Actualizar redirect_uris de 3 clientes
kubectl exec -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL psql -U kccentral -d iamcentralidp -c \
  "UPDATE redirect_uris SET value = 'http://portal.51.75.198.189.nip.io/*' 
   WHERE client_id IN (
     SELECT id FROM client WHERE client_id IN ('Cl1-CX-Registration', 'Cl2-CX-Portal', 'Cl3-CX-Semantic')
   );"

# 3. Actualizar identity_provider_config (URLs del Shared IDP)
kubectl exec -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL psql -U kccentral -d iamcentralidp -c \
  "UPDATE identity_provider_config 
   SET value = REPLACE(value, 'sharedidp.tx.test', 'sharedidp.51.75.198.189.nip.io')
   WHERE identity_provider_id IN (
     SELECT internal_id FROM identity_provider WHERE provider_alias = 'CX-Operator'
   )
   AND name IN ('tokenUrl', 'authorizationUrl', 'jwksUrl', 'logoutUrl');"
```

**Razón de estas correcciones**:
- `client.root_url`: Define la URL base del cliente para redirecciones
- `redirect_uris`: Lista blanca de URLs permitidas después de autenticación
- `identity_provider_config`: Endpoints OAuth del Shared IDP para federación

#### 7.3 Corregir Shared IDP Database

**Razón**: El cliente `central-idp` tiene redirect_uri y jwks.url apuntando a `centralidp.tx.test`.

```bash
# 1. Actualizar redirect_uri del cliente central-idp
kubectl exec -n portal portal-sharedidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_SHARED psql -U kcshared -d iamsharedidp -c \
  "UPDATE redirect_uris 
   SET value = 'http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/broker/CX-Operator/endpoint/*'
   WHERE client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');"

# 2. Actualizar jwks.url en client_attributes
kubectl exec -n portal portal-sharedidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_SHARED psql -U kcshared -d iamsharedidp -c \
  "UPDATE client_attributes 
   SET value = 'http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/protocol/openid-connect/certs'
   WHERE name = 'jwks.url' 
   AND client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');"
```

**Razón de estas correcciones**:
- `redirect_uris`: URL de callback después de autenticación en Shared IDP
- `jwks.url`: Endpoint para obtener claves públicas de Central IDP para verificar firmas JWT (autenticación entre Keycloaks)

#### 7.4 Reiniciar Pods de Keycloak

```bash
# Reiniciar para recargar configuración desde base de datos
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp

# Esperar a que estén ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=centralidp -n portal --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sharedidp -n portal --timeout=300s
```

## Paso 8: Verificar el Despliegue

```bash
# Verificar que todos los pods están running
kubectl get pods -n portal

# Verificar ingresses
kubectl get ingress -n portal

# Acceder al portal
echo "Portal: http://portal.51.75.198.189.nip.io"
echo "Central IDP: http://centralidp.51.75.198.189.nip.io/auth/"
echo "Shared IDP: http://sharedidp.51.75.198.189.nip.io/auth/"
echo "pgAdmin4: http://pgadmin4.51.75.198.189.nip.io"
```

## Paso 9: Probar el Flujo de Login

1. Abrir http://portal.51.75.198.189.nip.io
2. Hacer clic en "Login"
3. Hacer clic en "CX-Operator" (redirige a Shared IDP)
4. Autenticarse (usuario de test del realm CX-Operator)
5. Debe redirigir de vuelta al portal correctamente

## Credenciales de Administración

### Central IDP Admin
- URL: http://centralidp.51.75.198.189.nip.io/auth/
- Usuario: `admin`
- Password: `adminconsolepwcentralidp`
- Realm: `master`

### Shared IDP Admin
- URL: http://sharedidp.51.75.198.189.nip.io/auth/
- Usuario: `admin`
- Password: `adminconsolepwsharedidp`
- Realm: `master`

### pgAdmin4
- URL: http://pgadmin4.51.75.198.189.nip.io
- Usuario: `pgadmin4@txtest.org`
- Password: `adminpgadmin4`

## Notas Importantes

### Persistencia de Datos
⚠️ **Las bases de datos PostgreSQL NO tienen persistencia habilitada** (usan `emptyDir`). Los datos se pierden si los pods se reinician. Para producción, configurar persistencia con PVC.

### DNS con nip.io
Usamos el servicio nip.io que resuelve automáticamente subdominios a la IP:
- `*.51.75.198.189.nip.io` → `51.75.198.189`
- No requiere configuración DNS adicional
- Para producción, usar dominio real con certificados TLS

### Modo HTTP vs HTTPS
El despliegue usa HTTP sin TLS. Para habilitar HTTPS:
1. Obtener certificado TLS
2. Configurar Ingress con TLS
3. Cambiar todas las URLs de `http://` a `https://`
4. Cambiar `KEYCLOAK_PRODUCTION` a `"true"`
5. Remover `KC_HTTP_ENABLED`

### Actualizar el Despliegue

```bash
# Modificar values-ovh-hosts.yaml según necesidad
helm upgrade portal . \
  -f values-adopter-portal.yaml \
  -f values-ovh-hosts.yaml \
  -n portal

# Si cambias URLs, deberás volver a ejecutar las correcciones de base de datos
```

### Desinstalar

```bash
# Desinstalar portal
helm uninstall portal -n portal

# Eliminar namespace
kubectl delete namespace portal

# Eliminar Nginx Ingress Controller (opcional)
helm uninstall nginx-ingress -n ingress-nginx
kubectl delete namespace ingress-nginx
```

## Troubleshooting

### Error: "invalid_client" o "Client authentication failed"
- Verificar que las URLs en `client_attributes.jwks.url` están correctas
- Reiniciar pods de Keycloak

### Error: "Invalid parameter: redirect_uri"
- Verificar que `redirect_uris` en la base de datos tienen las URLs correctas
- Verificar que coinciden con la IP externa

### Pods en CrashLoopBackOff
```bash
# Ver logs del pod problemático
kubectl logs -n portal <pod-name> --previous

# Revisar eventos
kubectl describe pod -n portal <pod-name>
```

### LoadBalancer en estado Pending
- El LoadBalancer de OVH puede tardar 2-5 minutos en asignar IP
- Verificar cuota de LoadBalancers en OVH

### Bases de Datos Inaccesibles
```bash
# Verificar que los pods de PostgreSQL están running
kubectl get pods -n portal | grep postgresql

# Probar conexión
kubectl exec -n portal portal-centralidp-postgresql-0 -- psql -U kccentral -d iamcentralidp -c "SELECT 1;"
```
