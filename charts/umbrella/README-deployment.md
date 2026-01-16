# Guía de Despliegue con IP Dinámica

Este directorio contiene herramientas para flexibilizar el despliegue en diferentes entornos OVH con IPs dinámicas.

## Estructura de Archivos

### Archivos de Configuración
- **`values-hosts-template.yaml`** - Plantilla genérica con wildcards `${OVH_LB_IP}` y `${DNS_SUFFIX}`
- **`values-hosts.yaml`** - Archivo generado para cada despliegue (NO versionar en Git)
- **`values-ovh-hosts.yaml`** - Archivo original (mantener como referencia)

### Scripts
- **`get_loadbalancer_ip.sh`** - Obtiene la IP del LoadBalancer del cluster
- **`generate_values_hosts_file_from_template.sh`** - Genera el archivo YAML desde la plantilla usando variables de entorno

## Flujo de Trabajo de Despliegue

### 1. Crear Cluster en OVH
Crear el cluster a través de la interfaz web de OVH.

### 2. Configurar kubectl
Descargar el kubeconfig y configurar el acceso:

```bash
export KUBECONFIG=/path/to/kubeconfig-xxxx.yml
kubectl get nodes
```

### 3. Instalar Ingress Controller (si no existe)
Asegurarse de que el ingress-nginx está desplegado y tiene una IP de LoadBalancer:

```bash
kubectl get svc -n ingress-nginx
```

### 4. Generar archivo de valores

El proceso se realiza en 3 pasos manuales:

```bash
cd charts/umbrella
chmod +x *.sh

# Paso 1: Obtener la IP del LoadBalancer
LB_IP=$(./get_loadbalancer_ip.sh)
echo "IP detectada: $LB_IP"

# Paso 2: Configurar variables de entorno
export LB_IP
export DNS_SUFFIX="nip.io"  # Para desarrollo. Usar "catena-x.net" u otro para producción

# Paso 3: Generar el archivo de valores
./generate_values_hosts_file_from_template.sh
```

**Para producción**, cambiar el DNS_SUFFIX en el paso 2:
```bash
export DNS_SUFFIX="catena-x.net"  # o tu dominio personalizado
```

### 5. Verificar el archivo generado
```bash
cat values-hosts.yaml
```

### 6. Desplegar con Helm
```bash
helm upgrade --install portal . \
  -f values-adopter-portal.yaml \
  -f values-hosts.yaml \
  -n portal --create-namespace
```

## Variables de Configuración

### `${OVH_LB_IP}`
La dirección IP del LoadBalancer de OVH. Esta IP cambia con cada nuevo cluster.

**Ejemplos:**
- `51.75.198.189`
- `135.125.45.67`

### `${DNS_SUFFIX}`
El sufijo DNS a utilizar.

**Opciones comunes:**

| Sufijo | Uso | Descripción |
|--------|-----|-------------|
| `nip.io` | Desarrollo/Testing | Servicio gratuito de DNS wildcard. No requiere configuración DNS. |
| `sslip.io` | Desarrollo/Testing | Alternativa a nip.io |
| `catena-x.net` | Producción | Dominio personalizado (requiere configuración DNS) |
| `your-domain.com` | Producción | Tu propio dominio |

## URLs Generadas

Con IP `51.75.198.189` y sufijo `nip.io`, se generan URLs como:

- Portal: `http://portal.51.75.198.189.nip.io`
- Portal Backend: `http://portal-backend.51.75.198.189.nip.io`
- Central IDP: `http://centralidp.51.75.198.189.nip.io`
- Shared IDP: `http://sharedidp.51.75.198.189.nip.io`
- PGAdmin4: `http://pgadmin4.51.75.198.189.nip.io`

## Limpieza

Al eliminar el cluster desde la interfaz OVH, simplemente elimina el archivo generado:

```bash
rm values-hosts.yaml
```

El archivo de plantilla (`values-hosts-template.yaml`) se mantiene para el próximo despliegue.

## Configuración de Git

Añadir al `.gitignore`:

```gitignore
# Generated values files - do not commit
charts/umbrella/values-hosts.yaml
```

## Producción con Dominio Personalizado

Para producción con un dominio personalizado:

1. **Configurar DNS:** Crear registros DNS tipo A apuntando a la IP del LoadBalancer:
   ```
   portal.catena-x.net        A  51.75.198.189
   *.catena-x.net             A  51.75.198.189
   ```

2. **Generar valores:**
   ```bash
   ./generate-values-hosts.sh 51.75.198.189 catena-x.net
   ```

3. **Configurar TLS:** Usar cert-manager para certificados SSL automáticos.

## Troubleshooting

### No se detecta la IP automáticamente
```bash
# Verificar servicios LoadBalancer
kubectl get svc -A | grep LoadBalancer

# Ejecutar con IP manual
./generate-values-hosts.sh <IP_DETECTADA>
```

### Los scripts no tienen permisos de ejecución
```bash
chmod +x *.sh
```

### URLs no resuelven
- Verificar que el LoadBalancer tiene IP externa asignada
- Probar con `nslookup portal.<IP>.nip.io`
- Verificar que el ingress-nginx está funcionando

## Ejemplos Completos

### Ejemplo 1: Nuevo despliegue de desarrollo
```bash
# 1. Descargar kubeconfig
export KUBECONFIG=./kubeconfig-abc123.yml

# 2. Verificar conexión
kubectl get nodes

# 3. Generar valores (auto-detecta IP)
cd charts/umbrella
chmod +x *.sh
./generate_values_hosts.sh

# 4. Desplegar
helm upgrade --install portal . \
  -f values-adopter-portal.yaml \
  -f values-hosts.yaml \
  -n portal --create-namespace

# 5. Acceder
# Las URLs se muestran al final del script
```

### Ejemplo 2: Despliegue de producción
```bash
# 1. Obtener IP del LoadBalancer
LB_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# 2. Configurar DNS (externamente)
# porIr al directorio de scripts
cd charts/umbrella
chmod +x *.sh

# 4. Obtener IP del LoadBalancer
LB_IP=$(./get_loadbalancer_ip.sh)
echo "IP detectada: $LB_IP"

# 5. Configurar variables y generar valores
export LB_IP
export DNS_SUFFIX="nip.io"
./generate_values_hosts_file_from_template.sh

# 6. Desplegar
helm upgrade --install portal . \
  -f values-adopter-portal.yaml \
  -f values-hosts.yaml \
  -n portal --create-namespace

# 7. Acceder
echo "Portal: http://portal.$LB_IP.$DNS_SUFFIX"
```

### Ejemplo 2: Despliegue de producción
```bash
# 1. Configurar kubeconfig
export KUBECONFIG=./kubeconfig-abc123.yml

# 2. Obtener IP del LoadBalancer
cd charts/umbrella
LB_IP=$(./get_loadbalancer_ip.sh)
echo "IP del LoadBalancer: $LB_IP"

# 3. Configurar DNS manualmente (externamente)
# Crear registros A en tu proveedor DNS:
# portal.catena-x.net -> $LB_IP
# *.catena-x.net -> $LB_IP

# 4. Generar valores con dominio de producción
export LB_IP
export DNS_SUFFIX="catena-x.net"
./generate_values_hosts_file_from_template.sh

# 5