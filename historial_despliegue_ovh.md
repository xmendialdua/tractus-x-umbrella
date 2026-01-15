# Historial de Despliegue - Tractus-X Portal en OVH Kubernetes

**Fecha**: 15 de Enero de 2026  
**Objetivo**: Desplegar el portal de Tractus-X en cluster Kubernetes de OVH  
**Componentes**: portal, centralidp, sharedidp, pgadmin4

---

## Contexto del Proyecto

### Infraestructura
- **Cluster**: OVH Kubernetes (66vd7q.c1.gra.k8s.ovh.net)
- **Chart**: tractus-x-umbrella versión 3.14.5, Release 25.09
- **IP Externa LoadBalancer**: 51.75.198.189 (asignada por OVH)
- **DNS**: nip.io wildcard (*.51.75.198.189.nip.io)
- **Namespace**: portal
- **Ingress Controller**: nginx-ingress-controller

### Componentes Desplegados
- **Portal**: Frontend (React) + Backend (Spring Boot)
- **Central IDP**: Keycloak 25.0.6 para autenticación de usuarios
- **Shared IDP**: Keycloak 25.0.6 para federación entre organizaciones
- **PostgreSQL**: Bitnami chart sin persistencia (emptyDir)
- **pgAdmin4**: Herramienta de administración de bases de datos

---

## Cronología del Despliegue

### 1. Preparación Inicial
```bash
export KUBECONFIG=/ruta/al/kubeconfig-66vd7q.yml
kubectl get nodes  # ✓ Verificado acceso al cluster
```

### 2. Instalación de Nginx Ingress Controller
```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```
**Resultado**: IP externa asignada: 51.75.198.189

### 3. Preparación del Chart
```bash
cd charts/umbrella
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add tractusx-dev https://eclipse-tractusx.github.io/charts/dev
helm dependency update
```

### 4. Primer Despliegue
```bash
kubectl create namespace portal
helm install portal . \
  -f values-adopter-portal.yaml \
  -f values-ovh-hosts.yaml \
  -n portal
```

---

## Problemas Encontrados y Soluciones

### Problema 1: Cookie not found / Invalid redirect_uri

**Síntoma**: Al hacer clic en "Login" → "CX-Operator", aparecía error de cookie o redirect_uri inválido.

**Causa Raíz**: 
- El realm seeding de Keycloak es **idempotente**: solo crea datos, no actualiza
- Las URLs de clientes quedaron con valores por defecto `.tx.test`
- Aunque `values-ovh-hosts.yaml` tenía las URLs correctas, no se aplicaron a datos existentes

**URLs Incorrectas Identificadas**:
```
http://portal.tx.test
http://centralidp.tx.test
http://sharedidp.tx.test
```

**Deben ser**:
```
http://portal.51.75.198.189.nip.io
http://centralidp.51.75.198.189.nip.io
http://sharedidp.51.75.198.189.nip.io
```

---

### Problema 2: URLs en Base de Datos Central IDP

**Base de Datos**: `iamcentralidp`  
**Usuario**: `kccentral`

#### Tabla 1: `client` - root_url incorrecto
```sql
-- Problema detectado
SELECT client_id, root_url FROM client WHERE client_id = 'Cl2-CX-Portal';
-- Resultado: root_url = "http://portal.tx.test/home"

-- Solución aplicada
UPDATE client 
SET root_url = 'http://portal.51.75.198.189.nip.io/home' 
WHERE client_id = 'Cl2-CX-Portal';
```

**Explicación**: `root_url` define la URL base del cliente. Keycloak la usa para generar redirecciones.

#### Tabla 2: `redirect_uris` - URLs de callback incorrectas
```sql
-- Problema detectado
SELECT c.client_id, r.value 
FROM client c 
JOIN redirect_uris r ON c.id = r.client_id 
WHERE c.client_id IN ('Cl1-CX-Registration', 'Cl2-CX-Portal', 'Cl3-CX-Semantic');
-- Resultado: value = "http://portal.tx.test/*"

-- Solución aplicada (3 registros actualizados)
UPDATE redirect_uris 
SET value = 'http://portal.51.75.198.189.nip.io/*' 
WHERE client_id IN (
  SELECT id FROM client 
  WHERE client_id IN ('Cl1-CX-Registration', 'Cl2-CX-Portal', 'Cl3-CX-Semantic')
);
```

**Explicación**: `redirect_uris` es la lista blanca de URLs permitidas después de autenticación OAuth. Si la URL del portal no está en esta lista, Keycloak rechaza el redirect_uri.

#### Tabla 3: `identity_provider_config` - Endpoints del Shared IDP incorrectos
```sql
-- Problema detectado
SELECT ip.provider_alias, ipc.name, ipc.value
FROM identity_provider ip
JOIN identity_provider_config ipc ON ip.internal_id = ipc.identity_provider_id
WHERE ip.provider_alias = 'CX-Operator';
-- Resultado: 4 URLs con "sharedidp.tx.test"

-- Solución aplicada (4 registros actualizados)
UPDATE identity_provider_config 
SET value = REPLACE(value, 'sharedidp.tx.test', 'sharedidp.51.75.198.189.nip.io')
WHERE identity_provider_id IN (
  SELECT internal_id FROM identity_provider WHERE provider_alias = 'CX-Operator'
)
AND name IN ('tokenUrl', 'authorizationUrl', 'jwksUrl', 'logoutUrl');
```

**Explicación**: El Central IDP usa estos endpoints para comunicarse con el Shared IDP en el flujo de federación OAuth:
- `authorizationUrl`: Donde redirige al usuario para autenticarse
- `tokenUrl`: Donde intercambia el código por tokens
- `jwksUrl`: Donde obtiene claves públicas para verificar tokens
- `logoutUrl`: Donde redirige para logout federado

**Schema importante**: La tabla `identity_provider` usa `provider_alias` (NO `alias`). Este fue un error que nos causó problemas iniciales.

---

### Problema 3: URLs en Base de Datos Shared IDP

**Base de Datos**: `iamsharedidp`  
**Usuario**: `kcshared`

#### Tabla 1: `redirect_uris` - Callback del Central IDP incorrecto
```sql
-- Problema detectado
SELECT c.client_id, r.value
FROM client c 
JOIN redirect_uris r ON c.id = r.client_id
WHERE c.client_id = 'central-idp';
-- Resultado: "http://centralidp.tx.test/auth/realms/CX-Central/broker/CX-Operator/endpoint/*"

-- Solución aplicada
UPDATE redirect_uris 
SET value = 'http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/broker/CX-Operator/endpoint/*'
WHERE client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');
```

**Explicación**: Después de autenticarse en Shared IDP, el usuario es redirigido de vuelta a este endpoint en Central IDP. La URL debe estar en la lista blanca.

#### Tabla 2: `client_attributes` - JWKS URL incorrecto (CRÍTICO)
```sql
-- Problema detectado
SELECT c.client_id, cc.name, cc.value
FROM client c 
JOIN client_attributes cc ON c.id = cc.client_id
WHERE c.client_id = 'central-idp' AND cc.name = 'jwks.url';
-- Resultado: "http://centralidp.tx.test/auth/realms/CX-Central/protocol/openid-connect/certs"

-- Solución aplicada
UPDATE client_attributes 
SET value = 'http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/protocol/openid-connect/certs'
WHERE name = 'jwks.url' 
AND client_id IN (SELECT id FROM client WHERE client_id = 'central-idp');
```

**Explicación CRÍTICA**: 
- El cliente `central-idp` usa autenticación `client-jwt`
- En lugar de enviar un secreto, firma un JWT con su clave privada
- El Shared IDP debe verificar esa firma obteniendo la clave pública del endpoint JWKS
- Si la URL JWKS es incorrecta, falla con: `UnknownHostException: centralidp.tx.test`
- **Este fue el último error que resolvimos**

**Atributos del cliente**:
```
backchannel.logout.revoke.offline.tokens = false
backchannel.logout.session.required = true
jwks.url = http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/protocol/openid-connect/certs
post.logout.redirect.uris = +
token.endpoint.auth.signing.alg = RS256
use.jwks.url = true
```

---

### Problema 4: Caché de Configuración en Keycloak

**Síntoma**: Después de corregir URLs en base de datos, el error persistía.

**Causa**: Keycloak mantiene configuración en memoria/caché.

**Solución**: Reiniciar pods para forzar recarga desde base de datos.
```bash
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
```

---

## Configuración Final - values-ovh-hosts.yaml

### Sección Portal
```yaml
portal:
  portalAddress: "http://portal.51.75.198.189.nip.io"
  portalBackendAddress: "http://portal-backend.51.75.198.189.nip.io"
  centralidp:
    address: "http://centralidp.51.75.198.189.nip.io"
  sharedidpAddress: "http://sharedidp.51.75.198.189.nip.io"
  frontend:
    ingress:
      className: "nginx"
  backend:
    ingress:
      className: "nginx"
```

### Sección Central IDP
```yaml
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
      - name: KEYCLOAK_PROXY_ADDRESS_FORWARDING
        value: "true"
      - name: KC_SPI_STICKY_SESSION_ENCODER_INFINISPAN_SHOULD_ATTACH_ROUTE
        value: "false"
      - name: KEYCLOAK_PRODUCTION
        value: "false"
      - name: KC_HTTP_ENABLED
        value: "true"
    realmSeeding:
      clients:
        portal:
          rootUrl: http://portal.51.75.198.189.nip.io/home
          redirects:
            - http://portal.51.75.198.189.nip.io/*
      sharedidp: "http://sharedidp.51.75.198.189.nip.io"
      identityProviders:
        - alias: "CX-Operator"
          config:
            tokenUrl: "http://sharedidp.51.75.198.189.nip.io/auth/realms/CX-Operator/protocol/openid-connect/token"
            authorizationUrl: "http://sharedidp.51.75.198.189.nip.io/auth/realms/CX-Operator/protocol/openid-connect/auth"
            jwksUrl: "http://sharedidp.51.75.198.189.nip.io/auth/realms/CX-Operator/protocol/openid-connect/certs"
            logoutUrl: "http://sharedidp.51.75.198.189.nip.io/auth/realms/CX-Operator/protocol/openid-connect/logout"
```

**Nota**: La sección `identityProviders` se añadió al final para intentar que el realm seeding configure estos endpoints. Sin embargo, debido a la idempotencia, es posible que no se aplique en despliegues sobre datos existentes.

### Sección Shared IDP
```yaml
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
          clients:
            central:
              redirects:
                - http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/broker/CX-Operator/endpoint/*
              clientAuthenticatorType: "client-jwt"
              attributes:
                jwks.url: "http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/protocol/openid-connect/certs"
                use.jwks.url: "true"
```

**Nota**: Similar al Central IDP, esta configuración puede no aplicarse sobre datos existentes.

---

## Job Automático de Corrección

**Archivo**: `fix-keycloak-urls-job.yaml`

Este Job de Kubernetes automatiza todas las correcciones SQL:

```bash
# Aplicar el Job
kubectl apply -f fix-keycloak-urls-job.yaml -n portal

# Monitorear ejecución
kubectl logs -n portal job/fix-keycloak-urls -f

# Reiniciar pods después
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
```

**Características**:
- Espera a que PostgreSQL esté listo (initContainer)
- Ejecuta las 5 correcciones SQL en orden
- Muestra progreso con logs detallados
- Lee passwords automáticamente de secrets
- **Requiere actualizar variable `EXTERNAL_IP`** con tu IP de LoadBalancer

---

## Comandos Útiles de Troubleshooting

### Verificar Estado del Despliegue
```bash
# Ver todos los pods
kubectl get pods -n portal

# Ver ingresses y sus URLs
kubectl get ingress -n portal

# Ver servicios
kubectl get svc -n portal
```

### Acceder a Bases de Datos
```bash
# Obtener password de Central IDP
PGPASSWORD_CENTRAL=$(kubectl get secret -n portal portal-centralidp-postgresql \
  -o jsonpath='{.data.password}' | base64 -d)

# Conectarse a Central IDP database
kubectl exec -it -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL psql -U kccentral -d iamcentralidp

# Obtener password de Shared IDP
PGPASSWORD_SHARED=$(kubectl get secret -n portal portal-sharedidp-postgresql \
  -o jsonpath='{.data.password}' | base64 -d)

# Conectarse a Shared IDP database
kubectl exec -it -n portal portal-sharedidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_SHARED psql -U kcshared -d iamsharedidp
```

### Consultas SQL Útiles

#### Verificar URLs de Clientes en Central IDP
```sql
-- Ver clientes del portal
SELECT client_id, root_url, base_url 
FROM client 
WHERE client_id LIKE 'Cl%';

-- Ver redirect URIs
SELECT c.client_id, r.value 
FROM client c 
JOIN redirect_uris r ON c.id = r.client_id 
WHERE c.client_id LIKE 'Cl%';

-- Ver identity provider config
SELECT ip.provider_alias, ipc.name, ipc.value
FROM identity_provider ip
JOIN identity_provider_config ipc ON ip.internal_id = ipc.identity_provider_id
WHERE ip.provider_alias = 'CX-Operator';
```

#### Verificar Cliente en Shared IDP
```sql
-- Ver cliente central-idp
SELECT client_id, client_authenticator_type 
FROM client 
WHERE client_id = 'central-idp';

-- Ver redirect URIs
SELECT c.client_id, r.value
FROM client c 
JOIN redirect_uris r ON c.id = r.client_id
WHERE c.client_id = 'central-idp';

-- Ver atributos del cliente (incluyendo jwks.url)
SELECT c.client_id, cc.name, cc.value
FROM client c 
JOIN client_attributes cc ON c.id = cc.client_id
WHERE c.client_id = 'central-idp';
```

### Ver Logs de Keycloak
```bash
# Logs de Central IDP
kubectl logs -n portal -l app.kubernetes.io/name=centralidp --tail=100

# Buscar errores específicos
kubectl logs -n portal -l app.kubernetes.io/name=centralidp --tail=200 | grep -i error

# Logs de Shared IDP
kubectl logs -n portal -l app.kubernetes.io/name=sharedidp --tail=100
```

---

## Credenciales de Acceso

### Central IDP Admin Console
- **URL**: http://centralidp.51.75.198.189.nip.io/auth/
- **Usuario**: admin
- **Password**: adminconsolepwcentralidp
- **Realm**: master (para administración)
- **Realm de aplicación**: CX-Central

### Shared IDP Admin Console
- **URL**: http://sharedidp.51.75.198.189.nip.io/auth/
- **Usuario**: admin
- **Password**: adminconsolepwsharedidp
- **Realm**: master (para administración)
- **Realm de aplicación**: CX-Operator

### pgAdmin4
- **URL**: http://pgadmin4.51.75.198.189.nip.io
- **Usuario**: pgadmin4@txtest.org
- **Password**: adminpgadmin4

### Portal
- **URL**: http://portal.51.75.198.189.nip.io
- **Login**: A través de CX-Operator (Shared IDP)
- Usuarios de test definidos en realm seeding

---

## Flujo de Autenticación OAuth Completo

### Descripción del Flujo
```
1. Usuario accede a Portal → http://portal.51.75.198.189.nip.io
2. Click en "Login"
3. Redirige a Central IDP → http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/...
4. Usuario hace clic en botón "CX-Operator" (Identity Provider)
5. Central IDP redirige a Shared IDP → http://sharedidp.51.75.198.189.nip.io/auth/realms/CX-Operator/...
6. Usuario se autentica en Shared IDP
7. Shared IDP genera código de autorización
8. Redirige de vuelta a Central IDP → http://centralidp.51.75.198.189.nip.io/auth/realms/CX-Central/broker/CX-Operator/endpoint
9. Central IDP intercambia código por token con Shared IDP:
   - Central IDP firma un JWT con su clave privada
   - Envía el JWT firmado al tokenUrl de Shared IDP
   - Shared IDP obtiene clave pública desde jwks.url de Central IDP
   - Shared IDP verifica la firma del JWT
   - Shared IDP devuelve tokens (access_token, id_token)
10. Central IDP crea sesión local
11. Redirige de vuelta al Portal → http://portal.51.75.198.189.nip.io/
12. Portal obtiene token de Central IDP
13. Usuario autenticado ✓
```

### Puntos Críticos del Flujo
- **redirect_uris**: Cada redirección debe estar en lista blanca
- **jwks.url**: Debe ser accesible para verificación de JWT
- **tokenUrl**: Debe estar correctamente configurado para intercambio de código
- **Cookies**: Keycloak usa cookies para mantener estado entre redirecciones

---

## Lecciones Aprendidas

### 1. Idempotencia del Realm Seeding
**Problema**: El realm seeding solo crea, nunca actualiza.
**Impacto**: URLs en values.yaml no se aplican a datos existentes.
**Solución**: Job automático o correcciones SQL manuales + restart.

### 2. Nombres de Columnas en PostgreSQL
**Problema**: Asumimos que la columna era `alias`, pero era `provider_alias`.
**Impacto**: Queries SQL fallaban.
**Solución**: Usar `\d table_name` para ver schema real.

### 3. Usuario de Base de Datos
**Problema**: Intentamos usar `bn_keycloak`, pero el usuario era `kccentral`/`kcshared`.
**Impacto**: No podíamos conectarnos.
**Solución**: Inspeccionar secrets y variables de entorno de pods.

### 4. Caché de Keycloak
**Problema**: Cambios en BD no se reflejaban inmediatamente.
**Impacto**: Pensábamos que las correcciones no funcionaban.
**Solución**: Siempre reiniciar pods después de cambios en BD.

### 5. Autenticación JWT entre Keycloaks
**Problema**: El error `UnknownHostException` no era obvio qué URL estaba mal.
**Impacto**: Tardamos en identificar que era el jwks.url.
**Solución**: Revisar logs completos y entender el flujo OAuth client-jwt.

### 6. Sin Persistencia en PostgreSQL
**Problema**: Los datos se pierden si los pods se reinician.
**Impacto**: Las correcciones SQL se pierden.
**Solución**: Para producción, habilitar persistencia con PVC. Para desarrollo, aceptar que es efímero.

---

## Arquitectura de Bases de Datos

### Database: iamcentralidp
```
Tablas principales:
├── client
│   ├── id (PK)
│   ├── client_id (ej: "Cl2-CX-Portal")
│   ├── root_url
│   ├── base_url
│   └── client_authenticator_type
├── redirect_uris
│   ├── client_id (FK → client.id)
│   └── value (ej: "http://portal.51.75.198.189.nip.io/*")
├── identity_provider
│   ├── internal_id (PK)
│   ├── provider_alias (ej: "CX-Operator")
│   └── enabled
└── identity_provider_config
    ├── identity_provider_id (FK → identity_provider.internal_id)
    ├── name (ej: "tokenUrl", "jwksUrl")
    └── value (URL del endpoint)
```

### Database: iamsharedidp
```
Tablas principales:
├── client
│   ├── id (PK)
│   ├── client_id (ej: "central-idp")
│   └── client_authenticator_type (ej: "client-jwt")
├── redirect_uris
│   ├── client_id (FK → client.id)
│   └── value
└── client_attributes
    ├── client_id (FK → client.id)
    ├── name (ej: "jwks.url", "use.jwks.url")
    └── value
```

---

## Estado Final del Despliegue

### ✅ Componentes Funcionando
- Portal frontend accesible
- Portal backend accesible
- Central IDP accesible y configurado
- Shared IDP accesible y configurado
- Flujo de login completo funcionando
- Federación OAuth entre Keycloaks funcionando
- pgAdmin4 accesible

### 🔧 Configuración Aplicada
- Nginx Ingress Controller con IP externa
- values-ovh-hosts.yaml con URLs correctas
- Correcciones SQL en ambas bases de datos
- Pods de Keycloak reiniciados

### 📝 Archivos Creados
1. **values-ovh-hosts.yaml**: Overrides de URLs para OVH
2. **fix-keycloak-urls-job.yaml**: Job automático de corrección
3. **despliegue_en_ovh.md**: Documentación completa de despliegue
4. **historial_despliegue_ovh.md**: Este archivo (historial de troubleshooting)

---

## URLs de Acceso Final

- **Portal**: http://portal.51.75.198.189.nip.io
- **Portal Backend**: http://portal-backend.51.75.198.189.nip.io
- **Central IDP**: http://centralidp.51.75.198.189.nip.io/auth/
- **Shared IDP**: http://sharedidp.51.75.198.189.nip.io/auth/
- **pgAdmin4**: http://pgadmin4.51.75.198.189.nip.io

---

## Próximos Pasos / Mejoras

### Para Producción
1. **Habilitar Persistencia**:
   ```yaml
   postgresql:
     primary:
       persistence:
         enabled: true
         size: 10Gi
         storageClass: "csi-cinder-high-speed"  # Ajustar según OVH
   ```

2. **Configurar TLS/HTTPS**:
   - Obtener certificados (Let's Encrypt con cert-manager)
   - Actualizar Ingress con TLS
   - Cambiar todas las URLs a https://
   - Configurar `KEYCLOAK_PRODUCTION: "true"`
   - Remover `KC_HTTP_ENABLED`

3. **Dominio Real**:
   - Registrar dominio (ej: portal.miempresa.com)
   - Configurar DNS apuntando a 51.75.198.189
   - Actualizar todos los valores en values-ovh-hosts.yaml

4. **Alta Disponibilidad**:
   - Aumentar réplicas de Keycloak
   - Configurar PostgreSQL con replicación
   - Configurar backups automáticos

5. **Monitoreo**:
   - Instalar Prometheus + Grafana
   - Configurar alertas
   - Dashboard de métricas de Keycloak

### Para Desarrollo
1. **Automatizar Correcciones**:
   - Integrar fix-keycloak-urls-job en Helm hooks
   - Ejecutar automáticamente post-install

2. **Mejorar Realm Seeding**:
   - Investigar si hay forma de forzar updates
   - Contribuir al proyecto upstream si es necesario

---

## Comandos de Mantenimiento

### Actualizar Despliegue
```bash
# Modificar values-ovh-hosts.yaml
helm upgrade portal . \
  -f values-adopter-portal.yaml \
  -f values-ovh-hosts.yaml \
  -n portal

# Si cambias URLs, aplicar correcciones
kubectl apply -f fix-keycloak-urls-job.yaml -n portal
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
```

### Backup Manual de Bases de Datos
```bash
# Backup Central IDP
kubectl exec -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL pg_dump -U kccentral iamcentralidp > backup-centralidp.sql

# Backup Shared IDP
kubectl exec -n portal portal-sharedidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_SHARED pg_dump -U kcshared iamsharedidp > backup-sharedidp.sql
```

### Restore de Bases de Datos
```bash
# Restore Central IDP
cat backup-centralidp.sql | kubectl exec -i -n portal portal-centralidp-postgresql-0 -- \
  env PGPASSWORD=$PGPASSWORD_CENTRAL psql -U kccentral -d iamcentralidp
```

### Desinstalar Completamente
```bash
# Desinstalar portal
helm uninstall portal -n portal

# Limpiar PVCs si existen
kubectl delete pvc -n portal --all

# Eliminar namespace
kubectl delete namespace portal

# Opcional: desinstalar nginx-ingress
helm uninstall nginx-ingress -n ingress-nginx
kubectl delete namespace ingress-nginx
```

---

## Referencias

### Documentación Oficial
- **Tractus-X Portal**: https://github.com/eclipse-tractusx/portal
- **Keycloak**: https://www.keycloak.org/documentation
- **Helm**: https://helm.sh/docs/

### Recursos Utilizados
- Chart: tractus-x-umbrella 3.14.5
- Keycloak: 25.0.6 (Bitnami)
- PostgreSQL: 15 (Bitnami)
- Nginx Ingress: stable

### Comunidad
- GitHub Issues: https://github.com/eclipse-tractusx/portal/issues
- Matrix Chat: #tractusx:matrix.eclipse.org

---

## Conclusión

El despliegue del portal Tractus-X en OVH Kubernetes se completó exitosamente después de resolver múltiples problemas relacionados con la configuración de URLs en las bases de datos de Keycloak.

**Tiempo total estimado**: ~4-6 horas (incluyendo troubleshooting)

**Principales desafíos**:
1. Idempotencia del realm seeding
2. Correcciones manuales en bases de datos
3. Configuración de autenticación JWT entre Keycloaks

**Soluciones implementadas**:
1. values-ovh-hosts.yaml con configuración completa
2. Job automático para correcciones SQL
3. Documentación detallada del proceso

El sistema está ahora funcional y listo para desarrollo. Para producción se recomienda implementar las mejoras listadas en "Próximos Pasos".

---

**Fecha de finalización**: 15 de Enero de 2026  
**Estado**: ✅ OPERATIVO
