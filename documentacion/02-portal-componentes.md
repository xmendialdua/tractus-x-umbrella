# 2. Portal y Componentes

## Introducción

El Portal Catena-X es la pieza central del ecosistema, proporcionando una interfaz web para la gestión de participantes del dataspace, así como los servicios core de identidad, trust y descubrimiento necesarios para el funcionamiento de los conectores EDC.

El Portal está desplegado en el namespace `portal` y consta de 7 bloques funcionales principales que trabajan de forma coordinada.

---

## Diagrama de Bloques Funcionales

📄 **Ver diagrama:** [diagramas/portal-bloques-funcionales.mmd](diagramas/portal-bloques-funcionales.mmd)

El diagrama muestra la arquitectura del Portal organizada en capas funcionales:

1. **Frontend Layer** - Interfaz de usuario web
2. **Backend Layer** - APIs y servicios de negocio
3. **Identity & Authentication** - Gestión de identidades (Keycloak)
4. **Trust & SSI** - Identidad auto-soberana y protocolo IATP
5. **Business Partners** - Gestión de datos de socios comerciales (BPDM)
6. **Discovery** - Servicios de descubrimiento de endpoints
7. **Data Storage** - Persistencia de datos (PostgreSQL y Vault)

---

## 1. Frontend Layer - Portal UI

### Portal Frontend

El frontend del Portal es una aplicación web moderna que proporciona la interfaz de usuario para:

- **Gestión de empresas**: Registro y onboarding de nuevas organizaciones
- **Gestión de usuarios**: Creación y administración de usuarios y roles
- **Gestión de conectores**: Registro y configuración de conectores EDC
- **Catálogo de servicios**: Navegación por servicios y aplicaciones disponibles
- **Panel de control**: Visualización del estado del dataspace

**Características técnicas:**
- Framework: React + TypeScript
- Puerto: 80
- URL: http://portal.51.178.94.25.nip.io
- Deployment: `portal-frontend`

### Portal NGINX

Servidor web que sirve los assets estáticos del frontend y actúa como proxy inverso.

---

## 2. Backend Layer - Servicios de API

El backend del Portal está compuesto por múltiples microservicios especializados:

### Portal Backend (API Gateway)

Servicio principal que expone las APIs REST para el frontend y coordina las operaciones entre servicios.

**Endpoints principales:**
- `/api/administration` - Gestión administrativa
- `/api/registration` - Procesos de registro
- `/api/apps` - Gestión de aplicaciones
- `/api/services` - Catálogo de servicios

**Configuración:**
- Puerto: 8080
- URL: http://portal-backend.51.178.94.25.nip.io/api
- Deployment: `portal-backend`
- Base de datos: PostgreSQL (`portal-backend`)

### Registration Service

Gestiona el proceso de onboarding de nuevas empresas en el dataspace:

1. Solicitud de registro de empresa
2. Validación de datos con BPDM
3. Creación de identidades en Keycloak
4. Emisión de credenciales verificables
5. Registro en servicios de descubrimiento

**Puerto:** 8080  
**Deployment:** `portal-registration-service`

### Administration Service

Proporciona funcionalidades de administración del portal:

- Gestión de usuarios y roles
- Configuración de organizaciones
- Asignación de permisos
- Gestión de conectores EDC
- Configuración de políticas

**Puerto:** 8080  
**Deployment:** `portal-administration-service`

### Notification Service

Sistema de notificaciones para alertas y mensajes:

- Notificaciones en la aplicación
- Envío de correos electrónicos
- Alertas de eventos del sistema
- Notificaciones de procesos de onboarding

**Puerto:** 8080  
**Deployment:** `portal-notification-service`

### Provisioning Service

Gestiona el aprovisionamiento automático de recursos:

- Creación de conectores EDC
- Configuración de identidades
- Asignación de recursos
- Gestión de suscripciones

**Puerto:** 8080  
**Deployment:** `portal-provisioning-service`

### Processes Worker

Worker en background para tareas asíncronas y procesos largos:

- Procesamiento de colas
- Tareas programadas
- Limpieza de datos
- Sincronizaciones periódicas

**Deployment:** `portal-processes-worker`

---

## 3. Identity & Authentication - Keycloak

El Portal utiliza dos instancias de Keycloak para gestionar la autenticación y autorización:

### Central IDP (Identity Provider Central)

**Propósito:** Gestión de identidades del operador del dataspace.

**Características:**
- Realm: `CX-Central`
- Usuarios: Administradores del portal y operadores
- Roles: Portal Admin, IT Admin, Business Admin
- Puerto: 8080
- URL: http://centralidp.51.178.94.25.nip.io/auth
- Deployment: `centralidp`
- Base de datos: PostgreSQL (`centralidp`)

**Funcionalidades:**
- Autenticación de administradores del portal
- Gestión de roles centrales
- Single Sign-On (SSO)
- Integración con LDAP/Active Directory (opcional)

### Shared IDP (Identity Provider Compartido)

**Propósito:** Gestión de identidades de empresas participantes del dataspace.

**Características:**
- Realm: `CX-Operator`
- Usuarios: Usuarios de empresas participantes
- Roles: Company Admin, App Developer, Business User
- Puerto: 8080
- URL: http://sharedidp.51.178.94.25.nip.io/auth
- Deployment: `sharedidp`
- Base de datos: PostgreSQL (`sharedidp`)

**Funcionalidades:**
- Autenticación de usuarios de empresas participantes
- Gestión de roles por organización
- Multi-tenancy
- Federación de identidades

### Integración con el Portal

```
Usuario → Portal Frontend → Central/Shared IDP → JWT Token → Backend APIs
```

Los tokens JWT emitidos por Keycloak incluyen:
- ID de usuario y organización
- Roles y permisos
- BPN (Business Partner Number) de la organización
- Claims personalizados

---

## 4. Trust & SSI - Self-Sovereign Identity

El bloque de Trust implementa el protocolo IATP (Identity and Trust Protocol) de Tractus-X para identidad descentralizada.

### SSI DIM Wallet Stub

**Propósito:** Gestión de DIDs (Decentralized Identifiers) y VCs (Verifiable Credentials).

**Características:**
- Puerto: 8080
- URL: http://ssi-dim-wallet-stub.51.178.94.25.nip.io
- Deployment: `ssi-dim-wallet-stub`
- Base de datos: PostgreSQL (`wallet`)
- Issuer BPN: `BPNL00000003CRHK`

**Funcionalidades:**
- **DID Management:** Creación y gestión de DIDs `did:web`
- **Credential Issuance:** Emisión de Verifiable Credentials
- **Credential Storage:** Almacenamiento de VCs
- **DID Resolution:** Resolución de documentos DID
- **Signature Verification:** Verificación de firmas digitales

**DIDs gestionados:**
```
did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL00000000MASS
did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL00000002IKLN
did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL00000003CRHK
did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL00000001CRHK
did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL000000015E3A
```

**Endpoints principales:**
- `GET /{bpn}/did.json` - Obtener DID Document
- `POST /api/presentations/query` - Solicitar Verifiable Presentation
- `POST /api/credentials/issuer` - Emitir credencial

### DIM Wallet Proxy

**Propósito:** Capa intermedia entre los conectores EDC y el Wallet Stub.

**Características:**
- Puerto: 8000
- URL interna: http://ssi-dim-wallet-proxy.portal.svc.cluster.local:8000
- Deployment: `ssi-dim-wallet-proxy`

**Funcionalidades:**
- Enrutamiento de peticiones al wallet
- Transformación de formatos
- Caché de respuestas
- Rate limiting

### BDRS (BPN-DID Resolution Service)

**Propósito:** Directorio para resolver BPNs a DIDs.

**Características:**
- Puerto: 8081
- URL: http://bdrs-server.51.178.94.25.nip.io
- Deployment: `bdrs-server`
- Storage: In-memory (bdrs-server-memory)

⚠️ **Importante:** BDRS usa almacenamiento en memoria, los datos se pierden al reiniciar el pod.

**API:**
```bash
# Consultar BPN
GET /api/directory?bpn=BPNL00000000MASS

# Respuesta
{
  "did": "did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:BPNL00000000MASS"
}
```

**Mappings actuales:**
- `BPNL00000000MASS` → `did:web:....:BPNL00000000MASS`
- `BPNL00000002IKLN` → `did:web:....:BPNL00000002IKLN`
- `BPNL00000003CRHK` → `did:web:....:BPNL00000003CRHK`

### SSI Credential Issuer

**Propósito:** Servicio de emisión de credenciales verificables.

**Características:**
- Puerto: 8080
- Deployment: `ssi-credential-issuer`

**Tipos de credenciales emitidas:**
- **Membership Credential:** Acredita membresía en el dataspace
- **BPN Credential:** Acredita el BPN de una organización
- **Framework Agreement Credential:** Acredita aceptación de acuerdos
- **Use Case Credential:** Acredita participación en casos de uso específicos

### Protocolo IATP (Identity and Trust Protocol)

El protocolo IATP define cómo los conectores EDC se autentican entre sí usando Verifiable Presentations:

**Flujo de autenticación:**

1. **Consumer EDC** solicita credenciales al Wallet Proxy
2. **Wallet Proxy** consulta el Wallet Stub
3. **Wallet Stub** genera una Verifiable Presentation (VP) con VCs
4. **Consumer EDC** envía la VP al Provider EDC
5. **Provider EDC** verifica la VP contra el Wallet Stub
6. **Provider EDC** valida las credenciales y autoriza la petición

📄 **Ver flujo completo:** [diagramas/catalog-request-sequence.mmd](diagramas/catalog-request-sequence.mmd)

---

## 5. Business Partners - BPDM

BPDM (Business Partner Data Management) gestiona el "Golden Record" de datos de socios comerciales.

### Arquitectura BPDM

```
Portal Backend → BPDM Gate → BPDM Pool → BPDM Cleaning/Bridge → PostgreSQL
```

### BPDM Gate

**Propósito:** Punto de entrada para datos de socios comerciales desde el portal.

**Características:**
- Puerto: 8081
- URL: http://business-partners.51.178.94.25.nip.io/companies/test-company
- Deployment: `bpdm-gate`

**Funcionalidades:**
- Recepción de datos de nuevas empresas
- Validación de formato
- Enrutamiento al Pool
- APIs para consulta de datos

**Endpoints principales:**
- `POST /api/catena/input/business-partners` - Crear/actualizar empresa
- `GET /api/catena/output/business-partners` - Consultar empresas
- `GET /api/catena/output/business-partners/{bpn}` - Consultar por BPN

### BPDM Pool

**Propósito:** Repositorio central del Golden Record de socios comerciales.

**Características:**
- Puerto: 8080
- Deployment: `bpdm-pool`
- Base de datos: PostgreSQL (`bpdm`)

**Funcionalidades:**
- Almacenamiento del Golden Record
- Gestión de BPNs (Business Partner Numbers)
- Deduplicación de datos
- APIs para búsqueda avanzada

**Tipos de datos gestionados:**
- **Legal Entity:** Entidades legales (empresas)
- **Site:** Ubicaciones/plantas
- **Address:** Direcciones físicas

### BPDM Cleaning Service

**Propósito:** Limpieza y validación de datos empresariales.

**Funcionalidades:**
- Normalización de direcciones
- Validación de datos fiscales
- Enriquecimiento de datos
- Detección de duplicados

### BPDM Bridge

**Propósito:** Sincronización de datos entre Gate y Pool.

**Funcionalidades:**
- Sincronización bidireccional
- Gestión de estado de sincronización
- Logs de cambios

### Integración con el Portal

Cuando una nueva empresa se registra en el Portal:

1. **Registration Service** envía datos a **BPDM Gate**
2. **BPDM Gate** valida y envía a **BPDM Pool**
3. **BPDM Pool** asigna un BPN único
4. **BPDM Pool** almacena el Golden Record
5. El BPN se devuelve al Portal
6. El Portal registra el BPN en BDRS con el DID correspondiente

---

## 6. Discovery Services

Los servicios de descubrimiento permiten localizar endpoints y resolver BPNs en el dataspace.

### Discovery Finder

**Propósito:** Servicio central para descubrir servicios de descubrimiento.

**Características:**
- Puerto: 8080
- Deployment: `discovery-finder`

**Funcionalidad:**
- Directorio de servicios de descubrimiento
- Registro de nuevos servicios
- Búsqueda por tipo de servicio

**API:**
```bash
# Buscar servicios de descubrimiento
GET /api/administration/connectors/discovery/search
```

### BPN Discovery

**Propósito:** Servicio para buscar BPNs basado en identificadores alternativos.

**Características:**
- Puerto: 8080
- Deployment: `bpn-discovery`

**Funcionalidad:**
- Búsqueda de BPN por identificadores (VAT, EORI, etc.)
- Registro de mappings BPN → Identificadores
- APIs para consulta

**Casos de uso:**
- Encontrar el BPN de un socio comercial conociendo su VAT
- Descubrir socios comerciales en el dataspace

---

## 7. Data Storage - Persistencia

### PostgreSQL Databases

El Portal utiliza múltiples bases de datos PostgreSQL para diferentes servicios:

| Base de datos | Servicio | Puerto | Propósito |
|---------------|----------|--------|-----------|
| `portal-backend` | Portal Backend | 5432 | Datos de aplicación, usuarios, organizaciones |
| `centralidp` | Central IDP | 5432 | Usuarios y roles del operador |
| `sharedidp` | Shared IDP | 5432 | Usuarios de empresas participantes |
| `wallet` | SSI Wallet Stub | 5432 | DIDs y Verifiable Credentials |
| `bpdm` | BPDM Pool | 5432 | Golden Record de socios comerciales |

**Características:**
- Versión: PostgreSQL 15
- Almacenamiento: PersistentVolumeClaim (5Gi)
- Tipo de disco: csi-cinder-high-speed
- Backups: Configurar según políticas operativas

### Vault - Secrets Management

**Propósito:** Almacenamiento seguro de secretos y credenciales.

**Características:**
- Puerto: 8200
- Deployment: `portal-keycloak-secret`
- Tipo: HashiCorp Vault

**Secretos gestionados:**
- Credenciales de bases de datos
- API Keys de servicios
- Certificados privados
- Tokens de integración

---

## URLs de Acceso

### URLs Públicas (Externas)

| Servicio | URL | Descripción |
|----------|-----|-------------|
| Portal Frontend | http://portal.51.178.94.25.nip.io | Interfaz web principal |
| Central IDP | http://centralidp.51.178.94.25.nip.io/auth | Keycloak operador |
| Shared IDP | http://sharedidp.51.178.94.25.nip.io/auth | Keycloak participantes |
| SSI Wallet Stub | http://ssi-dim-wallet-stub.51.178.94.25.nip.io | DIDs y VCs |
| BDRS | http://bdrs-server.51.178.94.25.nip.io | BPN→DID Resolution |
| BPDM | http://business-partners.51.178.94.25.nip.io | Golden Record API |

### URLs Internas (Cluster)

| Servicio | URL Interna | Puerto |
|----------|-------------|--------|
| Portal Backend | http://portal-backend.portal.svc.cluster.local | 8080 |
| DIM Wallet Proxy | http://ssi-dim-wallet-proxy.portal.svc.cluster.local | 8000 |
| BDRS | http://bdrs-server.portal.svc.cluster.local | 8081 |
| BPDM Gate | http://bpdm-gate.portal.svc.cluster.local | 8081 |
| BPDM Pool | http://bpdm-pool.portal.svc.cluster.local | 8080 |

---

## Configuración de Red

### Ingress

El Portal utiliza NGINX Ingress Controller para exponer servicios:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: portal-ingress
  namespace: portal
spec:
  ingressClassName: nginx
  rules:
  - host: portal.51.178.94.25.nip.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: portal-frontend
            port:
              number: 80
```

### Comunicación Inter-Service

Los servicios dentro del namespace `portal` se comunican directamente usando DNS de Kubernetes:

```
<service-name>.<namespace>.svc.cluster.local:<port>
```

### Comunicación con EDC Connectors

Los conectores EDC (namespace `umbrella`) acceden a los servicios del Portal:

- **BDRS:** Para resolver BPN → DID
- **Wallet Proxy:** Para obtener credenciales (IATP)
- **Wallet Stub:** Para verificar Verifiable Presentations

---

## Monitoreo y Logs

### Logs de Aplicación

Ver logs de un servicio:

```bash
# Portal Backend
kubectl logs -n portal deployment/portal-backend -f

# Central IDP
kubectl logs -n portal deployment/centralidp -f

# Wallet Stub
kubectl logs -n portal deployment/ssi-dim-wallet-stub -f
```

### Estado de Servicios

Verificar estado de los pods:

```bash
kubectl get pods -n portal
kubectl get deployments -n portal
kubectl get services -n portal
```

### Métricas

Los servicios exponen métricas en formato Prometheus:

- Portal Backend: `http://portal-backend:9090/metrics`
- Keycloak: `http://centralidp:8080/metrics`

---

## Próximos Pasos

Continúa con:
- **[Capítulo 3: Conectores EDC](03-conectores-edc.md)** - Arquitectura y configuración de IKLN y MASS
- **[Capítulo 4: Identidad y Trust](04-identidad-y-trust.md)** - Detalles del protocolo IATP y SSI
- **[Capítulo 7: Troubleshooting](07-troubleshooting.md)** - Resolución de problemas comunes
