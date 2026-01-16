# Guía para Actualizar URLs en la Base de Datos de Keycloak

## ¿Por qué es necesario este proceso?

Keycloak utiliza **realm seeding idempotente**, lo que significa que:

- ✅ **Crea** datos que no existen en la base de datos
- ❌ **NO actualiza** datos que ya existen en la base de datos

Por tanto, cuando cambias la IP del LoadBalancer (al crear un nuevo cluster OVH):

1. Los valores en `values-hosts.yaml` se actualizan correctamente ✅
2. Keycloak lee estos valores al iniciar
3. **PERO** las URLs ya almacenadas en PostgreSQL **NO se actualizan** ❌
4. El login y las redirecciones fallan porque apuntan a URLs antiguas

## ¿Qué hace el script?

El script `fix-keycloak-urls-job.yaml` es un **Kubernetes Job** que:

1. Se conecta a las bases de datos PostgreSQL de `centralidp` y `sharedidp`
2. Actualiza las siguientes URLs en la base de datos:
   - **Client root URLs** - URL raíz del portal
   - **Redirect URIs** - URLs de redirección OAuth
   - **Identity Provider URLs** - tokenUrl, authorizationUrl, jwksUrl, logoutUrl
   - **Client attributes** - jwks.url para validación de tokens

## ¿Cuándo ejecutar este script?

Debes ejecutarlo en los siguientes casos:

### 1. Después del primer despliegue en un cluster nuevo
```bash
# Después de:
helm upgrade --install portal . -f values-adopter-portal.yaml -f values-hosts.yaml -n portal
```

### 2. Cada vez que cambies de cluster OVH
- Nuevo cluster = Nueva IP del LoadBalancer
- Las URLs antiguas quedan en la base de datos

### 3. Si el login del portal no funciona
Síntomas:
- Errores de redirect_uri inválida
- Login loop (redirección infinita)
- Errores 400 en Keycloak

### 4. Después de cambiar el DNS_SUFFIX
Si pasas de `nip.io` (desarrollo) a un dominio personalizado (producción)

## ¿Cómo ejecutar el script?

### Paso 1: Verificar que el despliegue está completo

```bash
# Verificar que todos los pods están corriendo
kubectl get pods -n portal

# Especialmente PostgreSQL y Keycloak
kubectl get pods -n portal | grep -E 'postgresql|keycloak'
```

### Paso 2: Editar la IP en el archivo

**IMPORTANTE:** Antes de aplicar el Job, actualiza la IP en el archivo.

Edita `fix-keycloak-urls-job.yaml` línea 55:

```yaml
# CHANGE THIS: Replace with your LoadBalancer IP
- name: EXTERNAL_IP
  value: "51.83.104.91"  # <-- Cambiar por tu IP
```

**Para obtener tu IP actual:**
```bash
cd charts/umbrella
LB_IP=$(./get_loadbalancer_ip.sh)
echo "Tu IP es: $LB_IP"
```

### Paso 3: Aplicar el Job

```bash
kubectl apply -f fix-keycloak-urls-job.yaml -n portal
```

### Paso 4: Monitorizar la ejecución

```bash
# Ver logs en tiempo real
kubectl logs -n portal job/fix-keycloak-urls -f

# Verificar el estado
kubectl get jobs -n portal
kubectl get pods -n portal | grep fix-keycloak-urls
```

**Salida esperada:**
```
==========================================
Starting Keycloak URL Fix Job
External IP: 51.83.104.91
==========================================

=== FIXING CENTRAL IDP DATABASE ===

1. Updating client.root_url for Cl2-CX-Portal...
   ✓ root_url updated
2. Updating redirect_uris for portal clients...
   ✓ 3 redirect_uris updated
3. Updating identity_provider_config URLs for CX-Operator...
   ✓ 4 identity_provider_config URLs updated

=== FIXING SHARED IDP DATABASE ===

4. Updating redirect_uri for central-idp client...
   ✓ redirect_uri updated
5. Updating client_attributes.jwks.url for central-idp...
   ✓ jwks.url updated

==========================================
Keycloak URL Fix Completed Successfully
==========================================
```

### Paso 5: Reiniciar los pods de Keycloak

**Esto es OBLIGATORIO** para que los cambios surtan efecto:

```bash
# Reiniciar centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp

# Reiniciar sharedidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp

# Esperar a que estén listos
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=centralidp -n portal --timeout=300s
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sharedidp -n portal --timeout=300s
```

### Paso 6: Verificar que funciona

```bash
echo "Accede al portal en: http://portal.$LB_IP.nip.io"
```

Prueba:
1. Acceder al portal
2. Hacer login
3. Verificar que no hay errores de redirect

## Limpieza del Job

Una vez completado exitosamente, puedes eliminar el Job:

```bash
kubectl delete job fix-keycloak-urls -n portal
```

El Job no se ejecuta automáticamente de nuevo. Si necesitas volver a ejecutarlo:

```bash
# Primero eliminar el Job anterior
kubectl delete job fix-keycloak-urls -n portal

# Luego volver a aplicarlo
kubectl apply -f fix-keycloak-urls-job.yaml -n portal
```

## Troubleshooting

### El Job falla con "connection refused"

**Causa:** Las bases de datos PostgreSQL no están listas.

**Solución:**
```bash
# Verificar pods de PostgreSQL
kubectl get pods -n portal | grep postgresql

# Esperar a que estén ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n portal --timeout=300s
```

### El Job falla con "password authentication failed"

**Causa:** Los secrets de PostgreSQL no están configurados correctamente.

**Solución:**
```bash
# Verificar que los secrets existen
kubectl get secret -n portal | grep postgresql

# Si no existen, reinstalar el chart
helm upgrade --install portal . -f values-adopter-portal.yaml -f values-hosts.yaml -n portal
```

### Las URLs siguen sin funcionar después del Job

**Verificar:**

1. **¿Reiniciaste los pods de Keycloak?**
   ```bash
   kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
   kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
   ```

2. **¿La IP en el Job es correcta?**
   ```bash
   kubectl logs -n portal job/fix-keycloak-urls | grep "External IP"
   ```

3. **¿Los cambios se aplicaron en la base de datos?**
   ```bash
   # Ver logs completos del Job
   kubectl logs -n portal job/fix-keycloak-urls
   ```

### El Job se queda en estado "Pending"

**Causa:** Recursos insuficientes o problemas de scheduling.

**Solución:**
```bash
# Ver detalles del pod
kubectl describe pod -n portal -l job-name=fix-keycloak-urls

# Ver eventos
kubectl get events -n portal --sort-by='.lastTimestamp'
```

## Proceso completo de ejemplo

```bash
# 1. Obtener la IP del LoadBalancer
cd charts/umbrella
LB_IP=$(./get_loadbalancer_ip.sh)
echo "LoadBalancer IP: $LB_IP"

# 2. Editar fix-keycloak-urls-job.yaml
# Cambiar línea 55: value: "$LB_IP"

# 3. Aplicar el Job
kubectl apply -f fix-keycloak-urls-job.yaml -n portal

# 4. Monitorizar
kubectl logs -n portal job/fix-keycloak-urls -f

# 5. Reiniciar Keycloak
kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp

# 6. Esperar a que estén listos
kubectl get pods -n portal -w

# 7. Probar el portal
echo "Portal: http://portal.$LB_IP.nip.io"

# 8. Limpiar (opcional)
kubectl delete job fix-keycloak-urls -n portal
```

## Notas importantes

- ⚠️ **El Job debe ejecutarse DESPUÉS del primer despliegue**, no antes
- ⚠️ **Es obligatorio reiniciar los pods de Keycloak** después de ejecutar el Job
- ⚠️ **Actualiza la IP en el archivo** antes de cada ejecución
- ⚠️ **El Job puede tardar 1-2 minutos** en completarse
- ✅ **El Job es idempotente**: puedes ejecutarlo múltiples veces sin problemas
- ✅ **Los datos existentes no se pierden**, solo se actualizan las URLs

## Automatización futura

> **Nota:** Actualmente la IP debe actualizarse manualmente en el archivo. En el futuro, este proceso podría automatizarse creando una plantilla parametrizada similar a `values-hosts-template.yaml`.
