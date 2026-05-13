# Documentación del Sistema Catena-X - Portal y Conectores EDC

## 📋 Índice de Contenidos

Esta documentación describe el despliegue completo del Portal Catena-X junto con los conectores EDC de IKERLAN y MASS en el entorno OVH.

### Capítulos

1. **[Arquitectura General](01-arquitectura-general.md)**
   - Visión general del sistema
   - Diagrama de arquitectura completa
   - Namespaces y componentes principales
   - Flujo de comunicación entre componentes

2. **[Portal y Componentes](02-portal-componentes.md)**
   - Portal Frontend y Backend
   - Keycloak (Central IDP y Shared IDP)
   - BPDM (Business Partner Data Management)
   - Discovery Services (BDRS, BPN Discovery, Discovery Finder)
   - Otros componentes del ecosistema

3. **[Conectores EDC](03-conectores-edc.md)**
   - Conector IKLN (BPNL00000002IKLN)
   - Conector MASS (BPNL00000000MASS)
   - Control Plane y Data Plane
   - PostgreSQL y Vault
   - Configuración de comunicación

4. **[Identidad y Trust](04-identidad-y-trust.md)**
   - SSI DIM Wallet Stub
   - DIM Wallet Proxy
   - DIDs (Decentralized Identifiers)
   - BDRS (BPN-DID Resolution Service)
   - Verifiable Credentials

5. **[Despliegue](05-despliegue.md)**
   - Requisitos previos
   - Procedimientos de instalación con Helm
   - Scripts de despliegue
   - Validación post-despliegue

6. **[Configuración](06-configuracion.md)**
   - Helm values y personalización
   - Variables de entorno críticas
   - Certificados TLS
   - Ingress y networking
   - Secrets y ConfigMaps

7. **[Troubleshooting](07-troubleshooting.md)**
   - Problemas comunes y soluciones
   - Logs y diagnóstico
   - Casos resueltos
   - Herramientas de diagnóstico

8. **[Procedimientos Operativos](08-procedimientos-operativos.md)**
   - Seeding de datos (BDRS, Wallets, Business Partners)
   - Backups y restauración
   - Actualizaciones y upgrades
   - Monitoreo y alertas

---

## 🎯 Información del Sistema

- **Entorno:** OVH Kubernetes Cluster
- **IP Pública:** 51.178.94.25
- **Dominio Base:** `*.51.178.94.25.nip.io`
- **Namespaces Principales:**
  - `portal` - Portal y servicios de infraestructura
  - `umbrella` - Conectores EDC (IKLN y MASS)
- **Chart Version:** umbrella-0.4.x, dataspace-connector-bundle-1.2.1
- **EDC Version:** tractusx-connector 0.11.1

---

## 🔗 Enlaces Rápidos

### URLs de Servicios

- **Portal:** http://portal.51.178.94.25.nip.io
- **Central IDP:** http://centralidp.51.178.94.25.nip.io/auth
- **IKLN Connector (Control):** https://edc-ikln-control.51.178.94.25.nip.io
- **MASS Connector (Control):** https://edc-mass-control.51.178.94.25.nip.io
- **SSI Wallet Stub:** http://ssi-dim-wallet-stub.51.178.94.25.nip.io
- **BDRS Server:** http://bdrs-server.51.178.94.25.nip.io

### Repositorios y Referencias

- **Proyecto:** tractus-x-umbrella
- **Ubicación:** `/home/xmendialdua/projects/assembly/tractus-x-umbrella`

---

## 📝 Convenciones de Documentación

- Los comandos de ejemplo incluyen el `KUBECONFIG` path completo
- Los valores sensibles (passwords, API keys) se marcan como `changeme` o se referencian desde secrets
- Los diagramas se encuentran en la carpeta `diagramas/`
- Cada capítulo es independiente pero referencia otros cuando es necesario

---

## 🔄 Última Actualización

**Fecha:** 13 de Mayo de 2026  
**Estado:** Operativo - Problema EDC_IAM_DID_WEB_USE_HTTPS resuelto
