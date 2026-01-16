# Despliegue del Portal Tractus-X en OVH - 16 de Enero de 2026

## Resumen

Este documento describe el proceso completo de despliegue del Portal Tractus-X en un cluster de Kubernetes en OVH. Con este despliegue se han desplegado **los componentes básicos del portal**, incluyendo:

- Portal Frontend y Backend
- Keycloak (Central IDP y Shared IDP)
- PostgreSQL para ambas instancias de Keycloak
- Ingress controllers y configuración de LoadBalancer

El cluster de OVH asigna dinámicamente una IP al LoadBalancer, por lo que este proceso debe adaptarse a cada nuevo despliegue.

---

## Contexto del Despliegue Realizado

### ⚠️ Proceso Actual (NO RECOMENDADO)

Para este despliegue se utilizó el fichero **`values-ovh-hosts.yaml`** (generado manualmente ayer), modificando la IP anterior mediante un simple `replace`:

```bash
# LO QUE SE HIZO (NO ES EL PROCESO CORRECTO):
cd ~/projects/assembly/tractus-x-umbrella/charts/umbrella

# Se modificó manualmente values-ovh-hosts.yaml reemplazando la IP antigua
sed -i 's/51.75.198.189/51.83.104.91/g' values-ovh-hosts.yaml

# Despliegue con el archivo modificado
helm install portal . -f values-adopter-portal.yaml -f values-ovh-hosts.yaml -n portal --create-namespace
```

**Problemas de este enfoque:**
- Requiere edición manual del fichero
- No escala bien para múltiples despliegues
- Propenso a errores humanos
- No hay trazabilidad de los cambios

### ✅ Proceso Recomendado (USAR EN FUTUROS DESPLIEGUES)

El proceso correcto debe utilizar el sistema de plantillas y scripts desarrollados:

1. Usar **`values-hosts-template.yaml`** como base
2. Detectar automáticamente la IP del LoadBalancer con **`get_loadbalancer_ip.sh`**
3. Generar **`values-hosts.yaml`** con **`generate_values_hosts_file_from_template.sh`**
4. Desplegar con el archivo generado

Este proceso se detalla en la sección siguiente.

---

## Proceso Completo de Despliegue (RECOMENDADO)

### Prerrequisitos

- Cluster de Kubernetes en OVH operativo
- `kubectl` configurado y con acceso al cluster
- `helm` instalado (versión 3.x)
- Scripts de deployment en el directorio `charts/umbrella/`

### Paso 1: Desplegar el Ingress Controller

El ingress controller debe desplegarse primero para obtener la IP del LoadBalancer:

```bash
# Desplegar nginx ingress controller (si no está ya instalado)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace

# Esperar a que se asigne la IP del LoadBalancer
kubectl get svc -n ingress-nginx -w
```

### Paso 2: Obtener la IP del LoadBalancer

Una vez desplegado el ingress controller:

```bash
cd ~/projects/assembly/tractus-x-umbrella/charts/umbrella

# Ejecutar el script para detectar la IP automáticamente
./get_loadbalancer_ip.sh
```

**Salida esperada:**
```
Searching for ingress-nginx LoadBalancer service...
Found LoadBalancer IP: 51.83.104.91
```

**Verificación manual (opcional):**
```bash
kubectl get svc -n ingress-nginx
```

### Paso 3: Generar el Fichero values-hosts.yaml

Con la IP detectada, generar el fichero de configuración:

```bash
# Establecer las variables de entorno
export LB_IP=51.83.104.91
export DNS_SUFFIX=nip.io

# Generar values-hosts.yaml desde la plantilla
./generate_values_hosts_file_from_template.sh
```

**Salida esperada:**
```
=== Generating values-hosts.yaml from template ===
Input template: values-hosts-template.yaml
Output file: values-hosts.yaml
LB_IP: 51.83.104.91
DNS_SUFFIX: nip.io

✓ Template file exists: values-hosts-template.yaml (69420 bytes)
✓ Generated file exists: values-hosts.yaml (69337 bytes)
✓ All placeholders have been replaced
✓ File generation completed successfully

Generated configuration for:
  - Portal: http://portal.51.83.104.91.nip.io
  - Central IDP: http://centralidp.51.83.104.91.nip.io
  - Shared IDP: http://sharedidp.51.83.104.91.nip.io
```

**Verificación:**
```bash
# Comprobar que no quedan placeholders sin reemplazar
grep -E '\$\{.*\}' values-hosts.yaml

# Debe devolver líneas vacías (sin resultados)

# Verificar algunas URLs generadas
grep "portal\." values-hosts.yaml | head -5
```

### Paso 4: Desplegar el Portal con Helm

```bash
cd ~/projects/assembly/tractus-x-umbrella/charts/umbrella

# Instalar el chart del portal
helm install portal . \
  -f values-adopter-portal.yaml \
  -f values-hosts.yaml \
  -n portal --create-namespace
```

**Salida esperada:**
```
NAME: portal
LAST DEPLOYED: Thu Jan 16 XX:XX:XX 2026
NAMESPACE: portal
STATUS: deployed
REVISION: 1
```

### Paso 5: Verificar el Despliegue

**Comprobar estado de los pods:**
```bash
kubectl get pods -n portal

# Esperar a que todos los pods estén Running o Completed
kubectl get pods -n portal -w
```

**Verificar los pods críticos de Keycloak:**
```bash
kubectl get pods -n portal | grep -E 'centralidp|sharedidp'
```

**Salida esperada:**
```
portal-centralidp-0                               1/1     Running     0          5m
portal-centralidp-postgresql-0                    1/1     Running     0          5m
portal-centralidp-realm-seeding-2-xxxxx           0/1     Completed   0          4m
portal-sharedidp-0                                1/1     Running     0          5m
portal-sharedidp-postgresql-0                     1/1     Running     0          5m
portal-sharedidp-realm-seeding-2-xxxxx            0/1     Completed   0          4m
```

**Verificar los ingress:**
```bash
kubectl get ingress -n portal
```

**Acceso inicial al portal:**
```bash
# Probar acceso al portal
curl -I http://portal.51.83.104.91.nip.io
```

---

## Corrección de URLs en Bases de Datos de Keycloak

### Contexto del Problema

Después del despliegue inicial, algunas URLs en las bases de datos de Keycloak no se actualizan correctamente porque el proceso de **realm seeding es idempotente** (no reescribe datos existentes). Esto afecta principalmente a:

- URLs de redirect_uris
- URLs de identity providers
- Client root URLs
- JWKS URLs

### Paso 6: Verificar URLs en las Bases de Datos

Antes de aplicar correcciones, verificar qué URLs necesitan actualización:

```bash
cd ~/projects/assembly/tractus-x-umbrella/charts/umbrella

# Ejecutar el script de verificación
./check-keycloak-urls.sh
```

**Salida esperada (si hay URLs incorrectas):**
```
========================================
KEYCLOAK URL VERIFICATION
========================================

Target URL patterns:
  centralidp.51.83.104.91.nip.io
  sharedidp.51.83.104.91.nip.io
  portal.51.83.104.91.nip.io
  ...

Checking CENTRAL IDP database (iamcentralidp)...

1. Checking client.root_url:
 client_id |              root_url              
-----------+------------------------------------
 Cl2-CX-Portal | http://portal.tx.test/home

[PROBLEMATIC URL FOUND: contains 'tx.test']

2. Checking redirect_uris:
     client_id      |         redirect_uri          
--------------------+-------------------------------
 Cl1-CX-Registration | http://portal.tx.test/*
 Cl2-CX-Portal       | http://portal.tx.test/*
 Cl3-CX-Semantic     | http://portal.tx.test/*
 ...

[PROBLEMATIC URLS FOUND]

...
```

**Si el script reporta URLs con `tx.test`**, es necesario ejecutar la corrección.

**Si todas las URLs son correctas:**
```
✅ All URLs are correctly configured
✅ No fixes needed
```

### Paso 7: Aplicar Corrección de URLs

Para corregir las URLs incorrectas, se utiliza el Kubernetes Job `fix-keycloak-urls-job-complete.yaml`.

#### 7.1. Configurar las Variables de Entorno en el Job

Editar el fichero para actualizar las variables de entorno:

```bash
nano fix-keycloak-urls-job-complete.yaml
```

**Buscar las líneas (alrededor de la línea 53-57):**
```yaml
            # CHANGE THIS: Replace with your LoadBalancer IP
            - name: EXTERNAL_IP
              value: "51.83.104.91"
            # DNS Suffix (change for production)
            - name: DNS_SUFFIX
              value: "nip.io"
```

**Actualizar con la IP correcta de tu LoadBalancer.**

#### 7.2. Aplicar el Job

```bash
# Aplicar el job de corrección
kubectl apply -f fix-keycloak-urls-job-complete.yaml -n portal

# Verificar que el job se ha creado
kubectl get jobs -n portal

# Ver los logs del job en tiempo real
kubectl logs -n portal job/fix-keycloak-urls-complete -f
```

**Salida esperada del Job:**
```
==========================================
Starting Keycloak URL Fix Job (Complete)
External IP: 51.83.104.91
DNS Suffix: nip.io
==========================================

=== FIXING CENTRAL IDP DATABASE ===

1. Updating client.root_url for Cl2-CX-Portal...
   ✓ root_url updated

2. Updating redirect_uris for portal clients...
   ✓ 3 portal redirect_uris updated

3. Updating redirect_uris for BPDM Gate...
   ✓ BPDM Gate redirect_uri updated

...

==========================================
Keycloak URL Fix Completed Successfully
==========================================
```

#### 7.3. Reiniciar los Pods de Keycloak

**IMPORTANTE:** Los cambios en la base de datos no se aplican hasta que se reinicien los pods de Keycloak:

```bash
# Reiniciar centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp

# Reiniciar sharedidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp

# Esperar a que los pods se reinicien
kubectl get pods -n portal -w | grep -E 'centralidp|sharedidp'
```

**Verificar que los pods están Running:**
```bash
kubectl get pods -n portal | grep -E 'centralidp|sharedidp'
```

**Salida esperada:**
```
portal-centralidp-0                               1/1     Running     0          1m
portal-centralidp-postgresql-0                    1/1     Running     0          15m
portal-sharedidp-0                                1/1     Running     0          1m
portal-sharedidp-postgresql-0                     1/1     Running     0          15m
```

### Paso 8: Verificar las Correcciones

Después de reiniciar los pods, verificar que las URLs se actualizaron correctamente:

```bash
# Re-ejecutar el script de verificación
./check-keycloak-urls.sh
```

**Salida esperada:**
```
✅ All URLs are correctly configured with: 51.83.104.91.nip.io
✅ No problematic URLs found
```

**Verificar variables de entorno en los pods:**
```bash
kubectl exec -n portal \
  $(kubectl get pod -n portal -l app.kubernetes.io/name=centralidp -o jsonpath='{.items[0].metadata.name}') \
  -- env | grep KEYCLOAK
```

**Salida esperada:**
```
KEYCLOAK_FRONTEND_URL=http://centralidp.51.83.104.91.nip.io/auth/
KEYCLOAK_HOSTNAME=http://centralidp.51.83.104.91.nip.io/auth/
...
```

### Paso 9: Limpiar Cookies y Probar el Acceso

**IMPORTANTE:** Después de reiniciar los pods de Keycloak, es necesario limpiar las cookies del navegador:

1. **Opción 1:** Limpiar cookies del dominio:
   - Abrir DevTools (F12)
   - Application → Cookies
   - Eliminar todas las cookies de `*.nip.io`

2. **Opción 2:** Usar modo incógnito:
   - Abrir una ventana de incógnito
   - Acceder al portal

3. **Verificar acceso:**
   ```bash
   # Probar el portal
   curl -I http://portal.51.83.104.91.nip.io
   
   # Probar Keycloak central
   curl -I http://centralidp.51.83.104.91.nip.io/auth/
   ```

4. **Acceso desde el navegador:**
   - Portal: http://portal.51.83.104.91.nip.io
   - Keycloak Central: http://centralidp.51.83.104.91.nip.io/auth/
   - Keycloak Shared: http://sharedidp.51.83.104.91.nip.io/auth/

---

## Limpieza del Job de Corrección

Después de aplicar la corrección con éxito, limpiar el job:

```bash
# Eliminar el job completado
kubectl delete job fix-keycloak-urls-complete -n portal

# Verificar que se ha eliminado
kubectl get jobs -n portal
```

---

## Resumen de Scripts y Comandos

### Scripts Disponibles

| Script | Ubicación | Propósito |
|--------|-----------|-----------|
| `get_loadbalancer_ip.sh` | `charts/umbrella/` | Detecta automáticamente la IP del LoadBalancer |
| `generate_values_hosts_file_from_template.sh` | `charts/umbrella/` | Genera `values-hosts.yaml` desde la plantilla |
| `check-keycloak-urls.sh` | `charts/umbrella/` | Verifica URLs en las bases de datos de Keycloak |
| `fix-keycloak-urls.sh` | `charts/umbrella/` | Corrección rápida vía `kubectl exec` (alternativa al Job) |

### Ficheros de Configuración

| Fichero | Tipo | Propósito |
|---------|------|-----------|
| `values-hosts-template.yaml` | Template | Plantilla con variables `${OVH_LB_IP}` y `${DNS_SUFFIX}` |
| `values-hosts.yaml` | Generated | Fichero generado para el despliegue (NO versionar en git) |
| `values-ovh-hosts.yaml` | Legacy | Fichero manual usado en este despliegue (NO RECOMENDADO) |
| `values-adopter-portal.yaml` | Base | Configuración base del portal |
| `fix-keycloak-urls-job-complete.yaml` | Kubernetes Job | Job para corrección de URLs en bases de datos |

### Comandos Clave

```bash
# Obtener IP del LoadBalancer
./get_loadbalancer_ip.sh

# Generar configuración
export LB_IP=<IP_DETECTADA>
export DNS_SUFFIX=nip.io
./generate_values_hosts_file_from_template.sh

# Desplegar portal
helm install portal . -f values-adopter-portal.yaml -f values-hosts.yaml -n portal --create-namespace

# Verificar URLs
./check-keycloak-urls.sh

# Aplicar corrección de URLs
kubectl apply -f fix-keycloak-urls-job-complete.yaml -n portal
kubectl logs -n portal job/fix-keycloak-urls-complete -f

# Reiniciar Keycloak
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp

# Verificar corrección
./check-keycloak-urls.sh
```

---

## Troubleshooting

### Problema: Cookie Not Found al acceder a Keycloak

**Síntoma:**
```
ERROR [org.keycloak.services] (executor-thread-1) KC-SERVICES0014: 
Failed to authenticate: java.lang.RuntimeException: 
org.keycloak.authentication.AuthenticationFlowException: 
Cookie not found. Please enable cookies in your browser
```

**Causa:**
- Los pods de Keycloak no fueron reiniciados después de corregir las URLs en la base de datos
- Hay cookies obsoletas en el navegador de antes de la corrección
- Desajuste entre `KEYCLOAK_FRONTEND_URL` y las URLs en la base de datos

**Solución:**
1. Reiniciar los pods de Keycloak (ver Paso 7.3)
2. Limpiar cookies del navegador o usar modo incógnito
3. Verificar que `KEYCLOAK_FRONTEND_URL` coincide con las URLs corregidas:
   ```bash
   kubectl exec -n portal $(kubectl get pod -n portal -l app.kubernetes.io/name=centralidp -o jsonpath='{.items[0].metadata.name}') -- env | grep KEYCLOAK_FRONTEND_URL
   ```

### Problema: El Job de Corrección Falla con "Image Pull Error"

**Síntoma:**
```
Failed to pull image "bitnami/postgresql:15"
```

**Solución:**
Usar el script alternativo de corrección directa:
```bash
export EXTERNAL_IP=51.83.104.91
export DNS_SUFFIX=nip.io
./fix-keycloak-urls.sh
```

Este script ejecuta los comandos directamente en los pods existentes de PostgreSQL sin necesidad de crear un Job.

### Problema: LoadBalancer IP No Se Detecta

**Síntoma:**
```
ERROR: Could not detect LoadBalancer IP
```

**Solución:**
```bash
# Verificar manualmente el servicio
kubectl get svc -n ingress-nginx

# Buscar el EXTERNAL-IP
# Si aparece <pending>, esperar unos minutos

# Una vez visible, asignar manualmente
export LB_IP=<IP_VISIBLE>
```

### Problema: Placeholders No Reemplazados en values-hosts.yaml

**Síntoma:**
```
⚠ WARNING: Found unreplaced placeholders in values-hosts.yaml
```

**Solución:**
```bash
# Verificar que las variables están definidas
echo $LB_IP
echo $DNS_SUFFIX

# Si están vacías, definirlas:
export LB_IP=51.83.104.91
export DNS_SUFFIX=nip.io

# Regenerar el archivo
./generate_values_hosts_file_from_template.sh
```

---

## Próximos Pasos

1. **Documentar credenciales:** Guardar de forma segura las credenciales de acceso (admin console, usuarios de prueba)

2. **Configurar TLS:** Para entornos de producción, configurar certificados TLS usando cert-manager:
   ```bash
   helm install portal . -f values-adopter-portal.yaml -f values-hosts.yaml -f values-tls.yaml -n portal
   ```

3. **Monitorización:** Configurar observabilidad con:
   ```bash
   helm install portal . -f values-adopter-portal.yaml -f values-hosts.yaml -f values-adopter-data-exchange-observability.yaml -n portal
   ```

4. **Backup de Bases de Datos:** Implementar backup periódico de las bases de datos de Keycloak:
   ```bash
   kubectl exec -n portal portal-centralidp-postgresql-0 -- pg_dump -U kccentral iamcentralidp > backup-centralidp.sql
   kubectl exec -n portal portal-sharedidp-postgresql-0 -- pg_dump -U kcshared iamsharedidp > backup-sharedidp.sql
   ```

---

## Referencias

- [Documentación oficial de Tractus-X](https://eclipse-tractusx.github.io/)
- [Repositorio GitHub](https://github.com/eclipse-tractusx/tractus-x-umbrella)
- [README de despliegue](./README-deployment.md)
- [README de corrección de base de datos](./README-fix-database.md)
- [Guía de migración](../docs/admin/migration-guide.md)

---

**Fecha:** 16 de Enero de 2026  
**Cluster:** OVH Kubernetes  
**LoadBalancer IP:** 51.83.104.91  
**DNS Suffix:** nip.io
