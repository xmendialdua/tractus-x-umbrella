# 🎯 Explicación Completa: Init-Container y URLs de Keycloak

## 📦 ¿Qué es el Init-Container?

El **init-container** es una **imagen Docker** que contiene archivos de configuración JSON para Keycloak. Su función es:

```
┌─────────────────────────────────────────────────────────────┐
│  Imagen Docker: tractusx/umbrella-init-container:2.3.0     │
│                                                             │
│  Contenido:                                                 │
│  /import/catenax-central/realms/                           │
│    ├── CX-Central-realm.json          ← Configuración      │
│    ├── CX-Central-realm_MAssembly.json   de Keycloak      │
│    └── CX-Central-users-0.json                             │
└─────────────────────────────────────────────────────────────┘
```

## 🔄 ¿Cómo Funciona el Proceso?

### Paso 1: Despliegue de Keycloak

```
Helm Chart Umbrella
    │
    ├─→ Despliegue de centralidp
    │       │
    │       └─→ Crea un Job: "portal-centralidp-realm-seeding-19"
    │               │
    │               └─→ Este Job tiene un INIT CONTAINER que:
    │                   1. Monta la imagen: tractusx/umbrella-init-container:2.3.0
    │                   2. Copia los archivos JSON a un volumen compartido
    │                   3. El contenedor principal de Keycloak lee esos JSON
    │                   4. Keycloak importa la configuración a PostgreSQL
```

### Paso 2: ¿Qué contiene CX-Central-realm.json?

```json
{
  "clients": [
    {
      "clientId": "Cl2-CX-Portal",
      "rootUrl": "http://portal.tx.test/home",     ← ❌ PROBLEMA
      "redirectUris": [
        "http://portal.tx.test/*"                  ← ❌ PROBLEMA
      ]
    },
    {
      "clientId": "Cl1-CX-Registration",
      "redirectUris": [
        "http://portal.tx.test/*"                  ← ❌ PROBLEMA
      ]
    }
  ],
  "identityProviders": [
    {
      "config": {
        "tokenUrl": "http://sharedidp.tx.test/auth/..."  ← ❌ PROBLEMA
      }
    }
  ]
}
```

### Paso 3: El Problema

```
Usuario intenta acceder → http://portal.51.68.114.44.nip.io
                                    │
                                    ↓
                  Keycloak verifica redirect_uri
                                    │
                                    ↓
        ¿La URL está en la lista de redirectUris permitidas?
                                    │
            ┌───────────────────────┴───────────────────────┐
            │                                               │
         ❌ NO                                           ✅ SÍ
            │                                               │
            ↓                                               ↓
  Error: "Invalid parameter:                      Login exitoso
         redirect_uri"
```

**Keycloak tiene en su BD:**
```
redirectUris: ["http://portal.tx.test/*"]
```

**Pero el usuario accede desde:**
```
http://portal.51.68.114.44.nip.io
```

**¡NO COINCIDE! → ERROR**

## 🛠️ ¿Por Qué Necesitamos una Imagen Personalizada?

### Opción A: Sin Imagen Personalizada (ACTUAL - MALO)

```
1. Helm despliegue usa imagen oficial: tractusx/umbrella-init-container:2.3.0
   └─→ Contiene URLs .tx.test

2. Keycloak importa: redirectUris = ["http://portal.tx.test/*"]

3. Usuario accede: http://portal.51.68.114.44.nip.io
   └─→ ❌ ERROR: redirect_uri no válido

4. Ejecutamos manualmente: fix-keycloak-urls-job-complete.yaml
   └─→ Script SQL actualiza BD: .tx.test → .51.68.114.44.nip.io

5. ✅ Funciona... HASTA el próximo helm upgrade

6. Helm upgrade → Vuelve a importar desde init-container
   └─→ Keycloak sobrescribe algunos valores a .tx.test
   └─→ ❌ ERROR de nuevo
   └─→ Hay que volver a ejecutar el job de corrección
```

### Opción B: Con Imagen Personalizada (NUEVA - BUENA)

```
1. Editamos CX-Central-realm.json LOCALMENTE:
   - Reemplazamos .tx.test → .51.68.114.44.nip.io
   
2. Construimos NUESTRA imagen:
   docker build -t miregistry/catena-x-init:ovh-v1 .
   
3. Subimos al registry:
   docker push miregistry/catena-x-init:ovh-v1

4. Configuramos values.yaml para usar NUESTRA imagen:
   centralidp:
     initContainer:
       image:
         repository: miregistry/catena-x-init
         tag: ovh-v1

5. Helm upgrade → Usa NUESTRA imagen
   └─→ Keycloak importa: redirectUris = ["http://portal.51.68.114.44.nip.io/*"]

6. Usuario accede: http://portal.51.68.114.44.nip.io
   └─→ ✅ FUNCIONA desde el primer momento

7. Futuros helm upgrade → Siguen usando NUESTRA imagen
   └─→ ✅ Siempre importa las URLs correctas
   └─→ ✅ NO necesitas ejecutar ningún job de corrección
```

## 📋 ¿Qué Contiene la Imagen Personalizada?

### Contenido EXACTO:

```
miregistry/catena-x-init:ovh-v1
│
└─── /import/catenax-central/realms/
      │
      ├─── CX-Central-realm.json  ← MODIFICADO con tus URLs
      │    {
      │      "clients": [
      │        {
      │          "clientId": "Cl2-CX-Portal",
      │          "rootUrl": "http://portal.51.68.114.44.nip.io/home",
      │          "redirectUris": ["http://portal.51.68.114.44.nip.io/*"]
      │        }
      │      ]
      │    }
      │
      ├─── CX-Central-realm_MAssembly.json  ← MODIFICADO
      │
      └─── CX-Central-users-0.json  ← SIN CAMBIOS (no tiene URLs)
```

### Comparación Imagen Oficial vs Personalizada:

| Archivo | Imagen Oficial | Tu Imagen Personalizada |
|---------|---------------|------------------------|
| Dockerfile | `FROM alpine:3.19`<br>`COPY iam/...` | `FROM alpine:3.19`<br>`COPY iam/...` |
| CX-Central-realm.json | `"http://portal.tx.test/*"` | `"http://portal.51.68.114.44.nip.io/*"` |
| CX-Central-realm_MAssembly.json | `"http://portal.tx.test/*"` | `"http://portal.51.68.114.44.nip.io/*"` |
| CX-Central-users-0.json | Sin cambios | Sin cambios |

**¡Es EXACTAMENTE la misma imagen!, solo cambian las URLs dentro de los JSON**

## 🚀 ¿Cómo se Utiliza?

### Paso 1: Actualizar los archivos JSON

```bash
cd /home/xmendialdua/projects/assembly/tractus-x-umbrella/init-container

# Ejecutar el script que creé para ti
./update-realm-urls.sh 51.68.114.44.nip.io

# Esto reemplaza TODAS las ocurrencias de .tx.test por .51.68.114.44.nip.io
# en los archivos JSON
```

### Paso 2: Construir TU imagen

```bash
# Necesitas un registry de Docker (DockerHub, Harbor, GitLab Registry, etc.)
# Ejemplo con DockerHub:

docker login  # Si no has hecho login

docker build -t xmendialdua/catena-x-init-ovh:v1.0.0 .

docker push xmendialdua/catena-x-init-ovh:v1.0.0
```

### Paso 3: Configurar values para usar tu imagen

Editar [values-ovh-hosts-portal.yaml](../charts/umbrella/values-ovh-hosts-portal.yaml):

```yaml
centralidp:
  initContainer:
    image:
      repository: "xmendialdua/catena-x-init-ovh"
      tag: "v1.0.0"

sharedidp:
  initContainer:
    image:
      repository: "xmendialdua/catena-x-init-ovh"
      tag: "v1.0.0"
```

### Paso 4: Helm upgrade

```bash
cd /home/xmendialdua/projects/assembly/tractus-x-umbrella/charts/umbrella

helm upgrade portal . -n portal \
  -f values-adopter-portal-for-onboarding.yaml \
  -f values-ovh-hosts-portal.yaml
```

### Paso 5: Verificar

```bash
# Esperar a que termine el realm-seeding job
kubectl wait --for=condition=complete job -l job-name=portal-centralidp-realm-seeding-20 -n portal --timeout=300s

# Verificar las URLs
./check-keycloak-urls.sh

# Debería mostrar TODAS las URLs con .51.68.114.44.nip.io
# Sin ninguna referencia a .tx.test
```

## 🎯 Resumen: ¿Problema y Solución?

### ❌ PROBLEMA:
- Imagen oficial tiene URLs de ejemplo (`.tx.test`)
- Keycloak importa esas URLs a su base de datos
- Tu portal usa dominio diferente (`.51.68.114.44.nip.io`)
- Keycloak rechaza el login porque la URL no coincide
- Tienes que corregir manualmente después de cada upgrade

### ✅ SOLUCIÓN:
- Crear TU PROPIA imagen con TUS URLs correctas
- Keycloak importa directamente TUS URLs desde el inicio
- Login funciona desde el primer momento
- No necesitas jobs de corrección manual
- Los upgrades futuros mantienen las URLs correctas

## 📊 Diagrama Flujo Completo

```
init-container/
├── iam/centralidp/CX-Central-realm.json
│   (Contiene URLs)
│
│   1. Editamos: .tx.test → .51.68.114.44.nip.io
│      (usando update-realm-urls.sh)
│
├── Dockerfile
│   (Copia los archivos JSON a la imagen)
│
│   2. Construimos imagen:
│      docker build -t mi-registro/init:v1
│
│   3. Subimos al registry:
│      docker push mi-registro/init:v1
│
values-ovh-hosts-portal.yaml
│   centralidp.initContainer.image = mi-registro/init:v1
│
│   4. Helm upgrade usa nuestra imagen
│
Kubernetes Job: portal-centralidp-realm-seeding-XX
│   initContainer monta: mi-registro/init:v1
│   Copia JSON al volumen
│
Keycloak lee JSON y importa a PostgreSQL
│   redirectUris = ["http://portal.51.68.114.44.nip.io/*"]
│
Usuario accede: http://portal.51.68.114.44.nip.io
│   ✅ Keycloak valida: URL coincide con redirectUris
│   ✅ Login exitoso
```

## 🤔 Preguntas Frecuentes

**P: ¿Tengo que pagar por un registry de Docker?**
R: No, puedes usar DockerHub gratuito (cuenta personal) o el registry de tu empresa.

**P: ¿Qué pasa si hago cambios en values.yaml?**
R: Los cambios en values.yaml NO afectan las URLs en realm.json. Por eso necesitas la imagen personalizada.

**P: ¿Tengo que reconstruir la imagen cada vez?**
R: Solo cuando cambies el dominio. Si usas siempre 51.68.114.44.nip.io, construyes la imagen UNA VEZ.

**P: ¿Puedo usar la imagen oficial + el job de corrección?**
R: Sí, pero tendrás que ejecutar el job manualmente después de algunos upgrades. Es tedioso y propenso a errores.

**P: ¿Qué tamaño tiene la imagen?**
R: ~10MB (solo contiene archivos JSON, no binarios).

## 📝 Siguiente Paso

¿Quieres que te ayude a:
1. Construir tu imagen personalizada ahora?
2. Configurar un registry de Docker?
3. Ejecutar el proceso completo paso a paso?
