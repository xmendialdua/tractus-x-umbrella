# 1. Arquitectura General del Sistema

## Visión General

El sistema consiste en un despliegue completo del ecosistema Catena-X que incluye:

1. **Portal Catena-X**: Interfaz web para gestión de participantes y datos
2. **Conectores EDC**: Dos conectores Eclipse Dataspace Components para intercambio de datos
3. **Servicios de Identidad y Trust**: Wallets, DIDs, y resolución BPN→DID
4. **Servicios de Descubrimiento**: BDRS, BPN Discovery, Discovery Finder
5. **Infraestructura**: Keycloak, PostgreSQL, Vault, Ingress

---

## Diagrama de Arquitectura Completa

```mermaid
graph TB
    subgraph "Internet"
        User[Usuario Web Browser]
        External[Conectores Externos]
    end

    subgraph "Ingress Layer - nginx (51.178.94.25)"
        Ingress[NGINX Ingress Controller]
    end

    subgraph "Namespace: portal"
        Portal[Portal Frontend]
        PortalBackend[Portal Backend]
        
        subgraph "Identity & Auth"
            CentralIDP[Central IDP<br/>Keycloak]
            SharedIDP[Shared IDP<br/>Keycloak]
        end
        
        subgraph "SSI & Trust"
            WalletStub[SSI DIM Wallet Stub]
            WalletProxy[DIM Wallet Proxy]
            BDRS[BDRS Server<br/>BPN→DID Resolution]
            CredIssuer[SSI Credential Issuer]
        end
        
        subgraph "BPDM Services"
            BPDMPool[BPDM Pool]
            BPDMGate[BPDM Gate]
            BPDMOrch[BPDM Orchestrator]
        end
        
        subgraph "Discovery Services"
            BPNDisc[BPN Discovery]
            DiscFinder[Discovery Finder]
        end
        
        subgraph "Databases - Portal"
            PortalDB[(Portal PostgreSQL)]
            BPDMDB[(BPDM PostgreSQL)]
            WalletDB[(Wallet PostgreSQL)]
        end
    end

    subgraph "Namespace: umbrella"
        subgraph "IKLN Connector - BPNL00000002IKLN"
            IKLNControl[Control Plane]
            IKLNData[Data Plane]
            IKLNPostgres[(PostgreSQL)]
            IKLNVault[Vault]
        end
        
        subgraph "MASS Connector - BPNL00000000MASS"
            MASSControl[Control Plane]
            MASSData[Data Plane]
            MASSPostgres[(PostgreSQL)]
            MASSVault[Vault]
        end
    end

    %% User connections
    User -->|HTTPS| Ingress
    External -->|HTTPS| Ingress
    
    %% Ingress routing
    Ingress -->|portal.*| Portal
    Ingress -->|centralidp.*| CentralIDP
    Ingress -->|edc-ikln-control.*| IKLNControl
    Ingress -->|edc-mass-control.*| MASSControl
    
    %% Portal connections
    Portal -->|API| PortalBackend
    PortalBackend -->|Auth| CentralIDP
    PortalBackend -->|BPDM| BPDMGate
    PortalBackend -->|Database| PortalDB
    
    %% EDC Connector connections
    IKLNControl -->|Catalog Request| MASSControl
    IKLNControl -->|DID Resolution| WalletProxy
    IKLNControl -->|BPN→DID| BDRS
    IKLNControl -->|Database| IKLNPostgres
    IKLNControl -->|Secrets| IKLNVault
    IKLNData -->|Data Transfer| MASSData
    
    MASSControl -->|DID Resolution| WalletProxy
    MASSControl -->|BPN→DID| BDRS
    MASSControl -->|Database| MASSPostgres
    MASSControl -->|Secrets| MASSVault
    
    %% Wallet & Identity
    WalletProxy -->|Proxy| WalletStub
    WalletStub -->|Database| WalletDB
    CredIssuer -->|Issue VCs| WalletStub
    
    %% BPDM connections
    BPDMGate -->|Pool API| BPDMPool
    BPDMPool -->|Orchestrator| BPDMOrch
    BPDMPool -->|Database| BPDMDB
    
    %% Discovery
    PortalBackend -->|Register| BPNDisc
    BPNDisc -->|Find| DiscFinder
    
    %% Styling
    classDef portalClass fill:#e1f5ff,stroke:#0288d1
    classDef edcClass fill:#fff3e0,stroke:#f57c00
    classDef identityClass fill:#f3e5f5,stroke:#7b1fa2
    classDef dbClass fill:#e8f5e9,stroke:#388e3c
    classDef ingressClass fill:#ffebee,stroke:#c62828
    
    class Portal,PortalBackend portalClass
    class IKLNControl,IKLNData,MASSControl,MASSData edcClass
    class CentralIDP,SharedIDP,WalletStub,WalletProxy,BDRS,CredIssuer identityClass
    class PortalDB,BPDMDB,WalletDB,IKLNPostgres,MASSPostgres dbClass
    class Ingress ingressClass
```

---

## Arquitectura Detallada del Portal (Namespace: portal)

El siguiente diagrama muestra la arquitectura interna del Portal Catena-X, incluyendo todos los servicios desplegados en el namespace `portal`. Los componentes están agrupados por su función dentro del ecosistema Tractus-X.

```mermaid
graph TB
    subgraph "PORTAL CATENA-X - Namespace: portal"
        
        subgraph "Frontend & UI Services"
            style Frontend_UI fill:#e3f2fd,stroke:#1976d2,stroke-width:3px
            Portal[Portal Frontend<br/>:80<br/>UI Application]
            PortalNginx[Portal NGINX<br/>:80<br/>Static Assets]
        end
        
        subgraph "Backend Services & APIs"
            style Backend_APIs fill:#e1f5fe,stroke:#0288d1,stroke-width:3px
            PortalBackend[Portal Backend<br/>:8080<br/>Main API Gateway]
            RegService[Registration Service<br/>:8080<br/>Company Onboarding]
            AdminService[Administration Service<br/>:8080<br/>User & Role Management]
            NotifService[Notification Service<br/>:8080<br/>Alerts & Messaging]
            ProvService[Provisioning Service<br/>:8080<br/>Resource Provisioning]
            ProcessWorker[Processes Worker<br/>Background Jobs]
        end
        
        subgraph "Identity & Access Management - IAM"
            style IAM fill:#fff3e0,stroke:#f57c00,stroke-width:3px
            CentralIDP[Central IDP<br/>Keycloak<br/>:8080<br/>Main Identity Provider<br/>Realm: CX-Central]
            SharedIDP[Shared IDP<br/>Keycloak<br/>:8080<br/>Partner Identity Provider<br/>Realm: CX-Operator]
            CentralIDPDB[(Central IDP DB<br/>PostgreSQL<br/>:5432)]
            SharedIDPDB[(Shared IDP DB<br/>PostgreSQL<br/>:5432)]
        end
        
        subgraph "SSI & Trust Layer - IATP Protocol"
            style SSI_Trust fill:#fce4ec,stroke:#c2185b,stroke-width:3px
            WalletStub[SSI DIM Wallet Stub<br/>:8080<br/>DID Management<br/>Verifiable Credentials<br/>Issuer: BPNL00000003CRHK]
            WalletProxy[DIM Wallet Proxy<br/>:8000<br/>Middleware Layer]
            BDRS[BDRS Server<br/>:8081<br/>BPN Directory Resolution<br/>BPN → DID Mapping]
            CredIssuer[SSI Credential Issuer<br/>:8080<br/>VC Issuance Service]
            WalletDB[(Wallet DB<br/>PostgreSQL<br/>:5432)]
        end
        
        subgraph "Business Partner Data Management - BPDM"
            style BPDM fill:#e8f5e9,stroke:#388e3c,stroke-width:3px
            BPDMGate[BPDM Gate<br/>:8081<br/>Company Entry Point]
            BPDMPool[BPDM Pool<br/>:8080<br/>Golden Record Pool]
            BPDMClean[BPDM Cleaning Service<br/>Data Validation]
            BPDMBridge[BPDM Bridge<br/>Data Synchronization]
            BPDMDB[(BPDM DB<br/>PostgreSQL<br/>:5432)]
        end
        
        subgraph "Discovery Services"
            style Discovery fill:#f3e5f5,stroke:#7b1fa2,stroke-width:3px
            DiscFinder[Discovery Finder<br/>:8080<br/>Endpoint Discovery]
            BPNDisc[BPN Discovery<br/>:8080<br/>BPN Lookup Service]
        end
        
        subgraph "Data Persistence Layer"
            style Persistence fill:#eceff1,stroke:#455a64,stroke-width:3px
            PortalDB[(Portal Backend DB<br/>PostgreSQL<br/>:5432<br/>Main Application Data)]
            Vault[Portal Keycloak Secret<br/>Vault<br/>:8200<br/>Secrets Management]
        end
    end
    
    %% Frontend connections
    Portal -->|API Calls| PortalBackend
    Portal -->|Static Content| PortalNginx
    
    %% Backend to IAM
    PortalBackend -->|Authentication| CentralIDP
    PortalBackend -->|Partner Auth| SharedIDP
    RegService -->|Create Users| CentralIDP
    AdminService -->|Manage Users| SharedIDP
    
    %% Backend to SSI/Trust
    PortalBackend -->|DID Operations| WalletProxy
    PortalBackend -->|BPN Resolution| BDRS
    WalletProxy -->|Proxy Requests| WalletStub
    CredIssuer -->|Issue VCs| WalletStub
    WalletStub -->|Store DIDs/VCs| WalletDB
    
    %% Backend to BPDM
    PortalBackend -->|Company Data| BPDMGate
    RegService -->|Register Company| BPDMGate
    BPDMGate -->|Validate & Store| BPDMPool
    BPDMPool -->|Data Cleaning| BPDMClean
    BPDMPool -->|Sync| BPDMBridge
    BPDMPool -->|Persistence| BPDMDB
    
    %% Backend to Discovery
    PortalBackend -->|Register Endpoints| BPNDisc
    PortalBackend -->|Find Services| DiscFinder
    BPNDisc -->|Query| DiscFinder
    
    %% Backend to Persistence
    PortalBackend -->|Application Data| PortalDB
    RegService -->|Store Registrations| PortalDB
    AdminService -->|Store Config| PortalDB
    NotifService -->|Store Notifications| PortalDB
    ProcessWorker -->|Process Jobs| PortalDB
    PortalBackend -->|Retrieve Secrets| Vault
    
    %% IAM to Persistence
    CentralIDP -->|User Data| CentralIDPDB
    SharedIDP -->|Partner Data| SharedIDPDB
    CentralIDP -->|Secrets| Vault
    SharedIDP -->|Secrets| Vault
    
    %% Styling
    classDef frontendStyle fill:#e3f2fd,stroke:#1976d2,stroke-width:2px
    classDef backendStyle fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    classDef iamStyle fill:#fff3e0,stroke:#f57c00,stroke-width:2px
    classDef trustStyle fill:#fce4ec,stroke:#c2185b,stroke-width:2px
    classDef bpdmStyle fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
    classDef discStyle fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef dbStyle fill:#eceff1,stroke:#455a64,stroke-width:2px
    
    class Portal,PortalNginx frontendStyle
    class PortalBackend,RegService,AdminService,NotifService,ProvService,ProcessWorker backendStyle
    class CentralIDP,SharedIDP iamStyle
    class WalletStub,WalletProxy,BDRS,CredIssuer trustStyle
    class BPDMGate,BPDMPool,BPDMClean,BPDMBridge bpdmStyle
    class DiscFinder,BPNDisc discStyle
    class PortalDB,CentralIDPDB,SharedIDPDB,WalletDB,BPDMDB,Vault dbStyle
```

### Descripción de los Bloques Funcionales

#### 1. Frontend & UI Services
Servicios de interfaz de usuario que proporcionan la experiencia web del Portal Catena-X.

#### 2. Backend Services & APIs
Conjunto de microservicios que implementan la lógica de negocio del portal, incluyendo onboarding de empresas, gestión de usuarios, notificaciones y aprovisionamiento de recursos.

#### 3. Identity & Access Management (IAM)
Dos instancias de Keycloak que gestionan la autenticación y autorización:
- **Central IDP**: Para usuarios del operador del dataspace
- **Shared IDP**: Para usuarios de empresas participantes

#### 4. SSI & Trust Layer (IATP Protocol)
Capa de identidad auto-soberana que implementa el protocolo IATP (Identity and Trust Protocol) de Tractus-X:
- **DIM Wallet Stub**: Gestión de DIDs (Decentralized Identifiers) y VCs (Verifiable Credentials)
- **BDRS**: Resolución de BPN (Business Partner Number) a DID
- **Credential Issuer**: Emisión de credenciales verificables

#### 5. Business Partner Data Management (BPDM)
Servicios para la gestión del "Golden Record" de datos de socios comerciales, incluyendo validación, limpieza y sincronización de datos empresariales.

#### 6. Discovery Services
Servicios de descubrimiento para localizar endpoints y resolver BPNs en el dataspace.

#### 7. Data Persistence Layer
Bases de datos PostgreSQL y Vault para almacenamiento persistente de datos de aplicación, identidades y secretos.

---

## Componentes Principales por Namespace

### Namespace: `portal`

| Componente | Propósito | URL Externa |
|------------|-----------|-------------|
| Portal Frontend | Interfaz web de usuario | http://portal.51.178.94.25.nip.io |
| Portal Backend | API y lógica de negocio | http://portal-backend.51.178.94.25.nip.io/api |
| Central IDP (Keycloak) | Autenticación centralizada | http://centralidp.51.178.94.25.nip.io/auth |
| Shared IDP (Keycloak) | IDP para partners | http://sharedidp.51.178.94.25.nip.io/auth |
| SSI DIM Wallet Stub | Gestión de DIDs y VCs | http://ssi-dim-wallet-stub.51.178.94.25.nip.io |
| DIM Wallet Proxy | Middleware para wallet | Interno |
| BDRS Server | Resolución BPN→DID | http://bdrs-server.51.178.94.25.nip.io |
| BPDM Pool/Gate/Orchestrator | Gestión de Business Partners | http://business-partners.51.178.94.25.nip.io |

### Namespace: `umbrella`

| Componente | Propósito | URL Externa |
|------------|-----------|-------------|
| IKLN Control Plane | Gestión de contratos y catálogos | https://edc-ikln-control.51.178.94.25.nip.io |
| IKLN Data Plane | Transferencia de datos | https://edc-ikln-data.51.178.94.25.nip.io |
| MASS Control Plane | Gestión de contratos y catálogos | https://edc-mass-control.51.178.94.25.nip.io |
| MASS Data Plane | Transferencia de datos | https://edc-mass-data.51.178.94.25.nip.io |

---

## Flujos de Comunicación Principales

### 1. Catalog Request (IKLN → MASS)

Flujo completo de una petición de catálogo desde el conector IKLN (Consumer) al conector MASS (Provider), incluyendo la obtención de credenciales mediante el protocolo IATP.

📄 **Ver diagrama de secuencia completo:** [diagramas/catalog-request-sequence.mmd](diagramas/catalog-request-sequence.mmd)

**Fases del flujo:**
1. **Obtención de Credenciales**: IKLN obtiene VP (Verifiable Presentation) del wallet a través del proxy
2. **Catalog Request con Autenticación**: IKLN envía la petición incluyendo el VP en las cabeceras
3. **Verificación y Respuesta**: MASS verifica las credenciales y devuelve el catálogo

### 2. BPN to DID Resolution

```mermaid
sequenceDiagram
    participant EDC as EDC Connector
    participant BDRS as BDRS Server
    participant Wallet as SSI Wallet Stub
    
    EDC->>BDRS: GET /api/directory?bpn=BPNL00000000MASS
    BDRS-->>EDC: did:web:ssi-dim-wallet-stub...:BPNL00000000MASS
    EDC->>Wallet: GET /BPNL00000000MASS/did.json
    Wallet-->>EDC: DID Document with public keys
```

---

## Configuraciones Críticas

### EDC_IAM_DID_WEB_USE_HTTPS

⚠️ **Configuración crítica para la resolución de DIDs**

| Componente | Valor | Razón |
|------------|-------|-------|
| IKLN Control Plane | `false` | Wallet stub está en HTTP |
| MASS Control Plane | `false` | Wallet stub está en HTTP |
| BDRS Server | `false` | Wallet stub está en HTTP |

**Problema resuelto:** IKLN tenía `true` inicialmente, causando errores 502 "Unable to obtain credentials: Empty optional".

### Namespaces y Networking

- **Comunicación intra-namespace:** `<service-name>.<namespace>.svc.cluster.local`
- **Ejemplo:** `http://bdrs-server.portal.svc.cluster.local:8082`
- **Ingress:** NGINX Ingress Controller gestiona todas las URLs externas

---

## Almacenamiento de Datos

### Datos Persistentes (PersistentVolumeClaims)

| Servicio | Namespace | Tamaño | Tipo |
|----------|-----------|---------|------|
| Portal PostgreSQL | portal | 5Gi | csi-cinder-high-speed |
| BPDM PostgreSQL | portal | 3Gi | csi-cinder-high-speed |
| Wallet PostgreSQL | portal | - | - |
| IKLN PostgreSQL | ikln-connector | 5Gi | csi-cinder-high-speed (legacy) |
| MASS PostgreSQL | mass-connector | 5Gi | csi-cinder-high-speed (legacy) |

⚠️ **Nota:** Los conectores en namespace `umbrella` usan `emptyDir` (efímero). Los PVCs en `ikln-connector` y `mass-connector` son legacy.

### Datos Efímeros (emptyDir)

- BDRS Server (datos en memoria, se pierden al reiniciar)
- Conectores EDC en namespace umbrella (si usan emptyDir)

---

## Seguridad y Trust

### Certificados TLS

- **Emisor:** Custom CA para el cluster
- **Secretos:**
  - `edc-ikln-control-tls`
  - `edc-ikln-data-tls`
  - `edc-mass-control-tls`
  - `edc-mass-data-tls`
  - `root-secret`

### Autenticación

- **Portal:** OAuth2/OIDC via Central IDP (Keycloak)
- **EDC Connectors:** Management API con API Key + IATP con DIDs/VPs
- **BDRS:** Token-based con header `x-api-key: TEST`

---

## Diagramas Detallados Adicionales

### 1. Componentes del Portal (Namespace: portal)

Diagrama detallado de todos los servicios desplegados en el namespace `portal`:

📄 **Ver diagrama:** [diagramas/portal-componentes.mmd](diagramas/portal-componentes.mmd)

Incluye:
- Frontend y UI Services
- Backend APIs
- Identity Providers (Keycloak)
- SSI & Trust Layer (Wallet, BDRS, Credential Issuer)
- BPDM Services
- Discovery Services
- Storage Layer (PostgreSQL databases)

---

### 2. Arquitectura del Conector IKLN

Diagrama interno del conector IKLN (Consumer):

📄 **Ver diagrama:** [diagramas/conector-ikln.mmd](diagramas/conector-ikln.mmd)

Incluye:
- Control Plane (Management API, DSP Protocol)
- Data Plane (Data Transfer)
- PostgreSQL y Vault
- Configuración y variables de entorno
- Dependencias externas

---

### 3. Arquitectura del Conector MASS

Diagrama interno del conector MASS (Provider):

📄 **Ver diagrama:** [diagramas/conector-mass.mmd](diagramas/conector-mass.mmd)

Incluye:
- Control Plane (Assets, Policies, DSP Protocol)
- Data Plane (Data Transfer)
- PostgreSQL y Vault
- Data Sources (Dashboard, Sharepoint, Partner Data)
- Configuración y variables de entorno

---

### 4. Diagrama de Subsistemas e Interacciones

Vista de alto nivel de las interacciones entre Portal, IKLN y MASS:

📄 **Ver diagrama:** [diagramas/subsistemas-interacciones.mmd](diagramas/subsistemas-interacciones.mmd)

Muestra:
- Ingress Layer y enrutamiento
- Portal Subsystem (Auth, Trust, Data)
- IKLN Connector Subsystem (Consumer)
- MASS Connector Subsystem (Provider)
- Flujo numerado de interacciones (1-9)

---

### 5. Diagrama de Secuencia: Catalog Request

Secuencia completa de una petición de catálogo desde IKLN a MASS:

📄 **Ver diagrama:** [diagramas/secuencia-catalog-request.mmd](diagramas/secuencia-catalog-request.mmd)

Pasos detallados:
1. Inicio de Catalog Request desde aplicación consumer
2. Resolución BPN → DID via BDRS
3. Obtención de DID Document
4. Obtención de Credenciales (IATP/VP)
5. Catalog Request via DSP Protocol
6. Validación del Consumer (VP signature + VCs)
7. Recuperación de Assets & Policies
8. Catalog Response
9. Respuesta al Consumer
10. Visualización en aplicación

---

## Próximos Pasos

Continúa con:
- **[Capítulo 2: Portal y Componentes](02-portal-componentes.md)** - Detalle de cada servicio del portal
- **[Capítulo 3: Conectores EDC](03-conectores-edc.md)** - Arquitectura interna de los conectores
- **[Capítulo 4: Identidad y Trust](04-identidad-y-trust.md)** - Sistema SSI completo
