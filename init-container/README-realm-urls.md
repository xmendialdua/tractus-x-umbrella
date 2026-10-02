# Solución al Problema de URLs .tx.test en Keycloak

## El Problema

Después de cada despliegue o upgrade de Helm, las URLs en Keycloak vuelven a tener el sufijo `.tx.test` en lugar del dominio correcto (ej: `.51.68.114.44.nip.io`), causando el error **"Invalid parameter: redirect_uri"**.

### Causa Raíz

Los archivos de realm seeding ([init-container/iam/centralidp/CX-Central-realm.json](../init-container/iam/centralidp/CX-Central-realm.json)) contienen URLs hardcodeadas con `.tx.test`:

```json
"redirectUris": [
  "http://portal.tx.test/*",
  "http://partners-gate.tx.test/*"
],
"tokenUrl": "http://sharedidp.tx.test/auth/realms/CX-Operator/protocol/openid-connect/token"
```

El init-container de Keycloak importa estos valores durante cada despliegue. Aunque Keycloak tiene lógica idempotente para realm seeding, algunos valores se reimportan cuando el chart detecta cambios.

## Soluciones

### Opción 1: Script Manual (Rápido)

Usar el script `update-realm-urls.sh` para actualizar los archivos realm.json **antes** de reconstruir el init-container:

```bash
cd init-container

# 1. Actualizar URLs en realm.json
./update-realm-urls.sh 51.68.114.44.nip.io

# 2. Revisar cambios
git diff iam/

# 3. Reconstruir imagen init-container
docker build -t <tu-registry>/init-container:v1.0.x .
docker push <tu-registry>/init-container:v1.0.x

# 4. Actualizar values.yaml
# Editar charts/umbrella/values-ovh-hosts-portal.yaml:
#
# centralidp:
#   initContainer:
#     image:
#       repository: <tu-registry>/init-container
#       tag: v1.0.x
#
# sharedidp:
#   initContainer:
#     image:
#       repository: <tu-registry>/init-container
#       tag: v1.0.x

# 5. Helm upgrade
cd ../charts/umbrella
helm upgrade portal . -n portal \
  -f values-adopter-portal-for-onboarding.yaml \
  -f values-ovh-hosts-portal.yaml \
  --set centralidp.initContainer.image.tag=v1.0.x \
  --set sharedidp.initContainer.image.tag=v1.0.x
```

### Opción 2: Script Automatizado (Recomendado)

Usar el script `update-and-deploy-realm.sh` que automatiza todo el proceso:

```bash
cd init-container

# Sintaxis:
# ./update-and-deploy-realm.sh <dominio> <registry> [tag]

# Ejemplo:
./update-and-deploy-realm.sh 51.68.114.44.nip.io myregistry.io/catena-x v1.0.1

# El script realiza automáticamente:
# 1. Actualiza realm.json con el nuevo dominio
# 2. Construye la imagen Docker
# 3. Sube la imagen al registry
# 4. Muestra instrucciones para helm upgrade
```

### Opción 3: Fix Job (Temporal - NO RECOMENDADO)

Si ya desplegaste sin actualizar realm.json, puedes ejecutar el job de corrección:

```bash
# Editar la IP en el archivo antes de aplicar
kubectl apply -f fix-keycloak-urls-job-complete.yaml -n portal
kubectl logs -n portal job/fix-keycloak-urls-complete -f

# Eliminar el job después
kubectl delete job fix-keycloak-urls-complete -n portal
```

**⚠️ LIMITACIÓN**: Este approach solo corrige la base de datos actual. En el próximo upgrade, los valores volverán a `.tx.test` si no se actualiza el init-container.

## Solución Definitiva

Para evitar este problema permanentemente:

### 1. **Actualizar realm.json una vez**

```bash
cd init-container
./update-realm-urls.sh 51.68.114.44.nip.io
git add iam/
git commit -m "feat: actualizar URLs de realm.json para dominio OVH"
```

### 2. **Usar imagen personalizada del init-container**

Crear tu propia imagen con los realm.json actualizados:

```bash
cd init-container
docker build -t tu-registry/catena-x-init-container:ovh-2026.01 .
docker push tu-registry/catena-x-init-container:ovh-2026.01
```

### 3. **Configurar values para usar tu imagen**

En [values-ovh-hosts-portal.yaml](../charts/umbrella/values-ovh-hosts-portal.yaml):

```yaml
centralidp:
  initContainer:
    image:
      repository: "tu-registry/catena-x-init-container"
      tag: "ovh-2026.01"

sharedidp:
  initContainer:
    image:
      repository: "tu-registry/catena-x-init-container"
      tag: "ovh-2026.01"
```

### 4. **Helm upgrade con la nueva configuración**

```bash
cd charts/umbrella
helm upgrade portal . -n portal \
  -f values-adopter-portal-for-onboarding.yaml \
  -f values-ovh-hosts-portal.yaml
```

## Verificación

Después del upgrade, verificar que las URLs estén correctas:

```bash
# Usar el script de verificación
./check-keycloak-urls.sh

# Debe mostrar todas las URLs con .51.68.114.44.nip.io
# Sin ninguna referencia a .tx.test
```

## Archivos Involucrados

| Archivo | Propósito | Ubicación |
|---------|-----------|-----------|
| `CX-Central-realm.json` | Configuración realm centralidp | [init-container/iam/centralidp/](../init-container/iam/centralidp/) |
| `CX-Central-realm_MAssembly.json` | Variante Assembly | [init-container/iam/centralidp/](../init-container/iam/centralidp/) |
| `update-realm-urls.sh` | Script para actualizar URLs | [init-container/](../init-container/) |
| `update-and-deploy-realm.sh` | Script automatizado completo | [init-container/](../init-container/) |
| `fix-keycloak-urls-job-complete.yaml` | Job corrección BD (temporal) | [charts/umbrella/](../charts/umbrella/) |
| `check-keycloak-urls.sh` | Script verificación URLs | [charts/umbrella/](../charts/umbrella/) |

## URLs Afectadas

Las siguientes URLs se actualizan en realm.json:

- **Portal**: `http://portal.tx.test/*` → `http://portal.51.68.114.44.nip.io/*`
- **BPDM Gate**: `http://partners-gate.tx.test/*` → `http://partners-gate.51.68.114.44.nip.io/*`
- **BPDM Pool**: `http://partners-pool.tx.test/*` → `http://partners-pool.51.68.114.44.nip.io/*`
- **Wallet**: `http://managed-identity-wallets.tx.test/*` → `http://managed-identity-wallets.51.68.114.44.nip.io/*`
- **SharedIDP**: `http://sharedidp.tx.test/auth/...` → `http://sharedidp.51.68.114.44.nip.io/auth/...`

## Clientes de Keycloak Afectados

- `Cl1-CX-Registration` (Portal registration)
- `Cl2-CX-Portal` (Portal frontend)
- `Cl3-CX-Semantic` (Semantic Hub)
- `Cl5-CX-Custodian` (Wallet)
- `Cl7-CX-BPDM` (BPDM Gate)
- `Cl16-CX-BPDMGate` (BPDM Gate client)
- `Cl21-CX-BPDMPool` (BPDM Pool)

## Conclusión

**La solución definitiva es actualizar los archivos realm.json en el init-container antes de construir la imagen**. Esto garantiza que las URLs correctas se importen desde el inicio, eliminando la necesidad de ejecutar jobs de corrección después de cada upgrade.

El job `fix-keycloak-urls-job-complete.yaml` debe considerarse solo como **solución de emergencia** para corregir instalaciones existentes, no como procedimiento estándar.
