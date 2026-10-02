# Espacio de datos de Mondragon Assembly

Este proyecto se ha utilizado para construir el **espacio de datos de Mondragon Assembly**, desplegado en una nube de **OVHcloud**. Incluye los charts Helm, configuraciones y scripts para desplegar el **Portal de Catena-X**, los **core services** de identidad, confianza y registro, y los **conectores EDC de los partners** del espacio de datos.

El desarrollo parte de un **fork de [Eclipse Tractus-X Umbrella](https://github.com/eclipse-tractusx/tractus-x-umbrella)**, basado en **[Tractus-X Release 25.09](https://github.com/eclipse-tractusx/tractus-x-release/blob/25.09/CHANGELOG.md)** (publicada el 1 de octubre de 2025). El chart principal es **Umbrella 3.14.5**, definido en [charts/umbrella/Chart.yaml](charts/umbrella/Chart.yaml). Las adaptaciones de este repositorio permiten utilizar estos componentes en la infraestructura y con los dominios del espacio de datos de Mondragon Assembly.

El detalle de las versiones de los componentes se recoge en [documentacion/2026.06.08 - Acerca de la version de Tractus-X.md](documentacion/2026.06.08%20-%20Acerca%20de%20la%20version%20de%20Tractus-X.md).

## Componentes del espacio de datos

Mediante este proyecto se despliega el Portal de Catena-X y los core services que permiten dar de alta a los partners, gestionar su identidad y desplegar y registrar sus conectores EDC:

- **Portal**: frontend y backend para la administracion del espacio de datos y el onboarding de los participantes.
- **CentralIDP y SharedIDP**: instancias de Keycloak para autenticacion y federacion de identidades.
- **BPDM, BPN Discovery y Discovery Finder**: gestion de datos de partners e identificacion y descubrimiento de participantes.
- **Servicios de identidad y confianza**: emisor de credenciales SSI, wallet DIM stub, proxy del wallet y BDRS para la resolucion BPN/DID. El wallet stub es un componente de simulacion, no un wallet DIM de produccion.
- **Self-Description Factory**: generacion de autodescripciones de los participantes.
- **Conectores EDC**: control plane, data plane, PostgreSQL y Vault propios para cada partner.

Tractus-X, el Portal y todos sus servicios centrales se han desplegado en el namespace `portal`, no en `umbrella`. El nombre de la release Helm es `umbrella`, pero no debe confundirse con el namespace. Posteriormente, los conectores EDC de los partners se han desplegado como releases Helm independientes en el namespace `umbrella`. El detalle del despliegue se recoge en [documentacion/2026.09.28-Piezas del despliege actual.md](documentacion/2026.09.28-Piezas%20del%20despliege%20actual.md).

## Accesos

El espacio de datos esta desplegado en un cluster Kubernetes de **OVHcloud**, con la IP publica **51.178.94.25** y el sufijo DNS **51.178.94.25.nip.io**.

| Servicio | Acceso |
| --- | --- |
| Administracion de la nube OVHcloud | [https://auth.eu.ovhcloud.com/signin/](https://auth.eu.ovhcloud.com/signin/) |
| Portal de Catena-X | [http://portal.51.178.94.25.nip.io](http://portal.51.178.94.25.nip.io/) |
| CentralIDP (Keycloak Administration Console) | [http://centralidp.51.178.94.25.nip.io/auth/admin/master/console/](http://centralidp.51.178.94.25.nip.io/auth/admin/master/console/) |
| SharedIDP (Keycloak Administration Console) | [http://sharedidp.51.178.94.25.nip.io/auth/admin/master/console/](http://sharedidp.51.178.94.25.nip.io/auth/admin/master/console/) |

Los accesos de administracion requieren las credenciales correspondientes. Las URLs HTTP reflejan la configuracion de este entorno; para un entorno de produccion se debe habilitar HTTPS y revisar los ajustes de seguridad de Keycloak.

## Despliegue del Portal de Catena-X en OVH

### 1. Preparar la infraestructura

Se necesita un cluster Kubernetes en OVHcloud, acceso mediante `kubectl`, Helm 3.8 o superior y Bash. La provision de infraestructura con Terraform se describe en [terraform-ovh/GUIA_TERRAFORM_OVH.md](terraform-ovh/GUIA_TERRAFORM_OVH.md).

Desde la raiz del repositorio, configurar el acceso al cluster con un kubeconfig valido:

```bash
export KUBECONFIG="$PWD/kubeconfig.yaml"
kubectl get nodes
```

Si el cluster todavia no tiene un ingress controller, instalarlo y esperar a que OVH asigne una IP externa al servicio LoadBalancer:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer
```

Consultar los servicios del ingress controller por separado:

```bash
kubectl get svc -n ingress-nginx
```

Resultado observado en este entorno (la antiguedad corresponde al momento de la consulta):

```text
NAME                                               TYPE           CLUSTER-IP    EXTERNAL-IP    PORT(S)                      AGE
nginx-ingress-ingress-nginx-controller             LoadBalancer   10.3.22.252   51.178.94.25   80:32485/TCP,443:31384/TCP   246d
nginx-ingress-ingress-nginx-controller-admission   ClusterIP      10.3.150.0    <none>         443/TCP                      246d
```

No reinstalar el ingress controller del entorno existente: en un nuevo despliegue la IP asignada puede ser distinta de `51.178.94.25`.

### 2. Generar la configuracion de dominios

El script [charts/umbrella/get_loadbalancer_ip.sh](charts/umbrella/get_loadbalancer_ip.sh) permite consultar la IP publica que OVH ha asignado al LoadBalancer. Esa es la IP que se debe utilizar en las URLs de acceso a los servicios. Desde la raiz del repositorio:

```bash
cd charts/umbrella
bash get_loadbalancer_ip.sh
```

En este caso la IP es **51.178.94.25**. Si se elimina el ingress controller y su servicio LoadBalancer creados en el punto anterior y se vuelven a crear, OVH asignara otra IP. En ese caso cambian las URLs de todos los servicios desplegados y se deben actualizar los valores de hosts y las configuraciones que conservan las URLs anteriores.

Como procedimiento de generacion desde plantilla, los siguientes comandos se ejecutan por separado, desde `charts/umbrella`:

```bash
export LB_IP="51.178.94.25"
export DNS_SUFFIX="nip.io"
bash generate_values_hosts_file_from_template.sh
```

Usar en `LB_IP` la IP real mostrada por [charts/umbrella/get_loadbalancer_ip.sh](charts/umbrella/get_loadbalancer_ip.sh). El script [charts/umbrella/generate_values_hosts_file_from_template.sh](charts/umbrella/generate_values_hosts_file_from_template.sh) genera el fichero de valores para Helm a partir de [charts/umbrella/values-hosts-template.yaml](charts/umbrella/values-hosts-template.yaml). Revisar los dominios y la configuracion generada antes de desplegar.

Este procedimiento de generacion se conserva como referencia. Para el despliegue realizado, los hosts de OVH se han definido directamente en [charts/umbrella/values-ovh-hosts-portal.yaml](charts/umbrella/values-ovh-hosts-portal.yaml), que es el manifiesto utilizado en el siguiente paso, no el fichero generado por estos comandos. Las aclaraciones al final del README describen el proceso inicial y el finalmente utilizado.

### 3. Instalar el chart y comprobar los servicios

Desde `charts/umbrella`, preparar las dependencias y desplegar el perfil de Portal:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add tractusx-dev https://eclipse-tractusx.github.io/charts/dev
helm repo update
helm dependency build .
helm upgrade --install portal . \
  -f values-adopter-portal-for-onboarding-with-persistence.yaml \
  -f values-ovh-hosts-portal.yaml \
  --namespace portal --create-namespace \
  --timeout 20m --wait
```

Una vez finalizada la instalacion, comprobar los servicios con comandos separados:

Resultados consultados el **2026-10-02** en el namespace `portal`. Son una captura del entorno existente, no una salida esperada invariable de una instalacion nueva; los nombres, estados y antiguedades pueden cambiar.

```bash
kubectl get pods -n portal
```

```text
NAME                                                          READY   STATUS      RESTARTS      AGE
bdrs-manual-seeding-v3-x62nd                                  0/1     Completed   0             77d
bdrs-server-6c799c7b5b-sb6k4                                  1/1     Running     0             78d
bpdm-postgres-0                                               1/1     Running     0             78d
dim-wallet-proxy-7fd5654d44-p6vmb                             1/1     Running     0             78d
portal-administration-service-5cd64495dc-jcbpl                1/1     Running     0             78d
portal-assets-667d84b5cd-p55k9                                1/1     Running     0             78d
portal-bpdm-cleaning-service-dummy-54d947c59f-nvsxv           1/1     Running     1 (78d ago)   78d
portal-bpdm-gate-687459c5b4-kqthb                             1/1     Running     1 (78d ago)   78d
portal-bpdm-orchestrator-6f5c646688-kr82h                     1/1     Running     0             78d
portal-bpdm-pool-7d4977d65c-v8g2x                             1/1     Running     0             78d
portal-bpndiscovery-67974f94d4-dr7qk                          1/1     Running     1 (78d ago)   78d
portal-bpndiscovery-postgresql-0                              1/1     Running     0             78d
portal-centralidp-0                                           1/1     Running     0             78d
portal-centralidp-postgresql-0                                1/1     Running     0             78d
portal-discoveryfinder-64b8c68b76-qn7xh                       1/1     Running     0             78d
portal-discoveryfinder-postgresql-0                           1/1     Running     0             78d
portal-issuer-postgresql-0                                    1/1     Running     0             78d
portal-marketplace-app-service-76d9c97bfc-pn79s               1/1     Running     0             78d
portal-notification-service-649694f9b5-2p9rk                  1/1     Running     0             78d
portal-pgadmin4-f5f4967d7-9cjt2                               1/1     Running     0             78d
portal-portal-backend-postgresql-0                            1/1     Running     0             78d
portal-portal-d6b48d9dc-krbs6                                 1/1     Running     0             78d
portal-portal-maintenance-29845440-g7m77                      0/1     Completed   0             2d10h
portal-portal-maintenance-29846880-d2hqr                      0/1     Completed   0             34h
portal-portal-maintenance-29848320-drccl                      0/1     Completed   0             10h
portal-processes-worker-29848965-slbwz                        0/1     Completed   0             13m
portal-processes-worker-29848970-q9glx                        0/1     Completed   0             8m33s
portal-processes-worker-29848975-qzvj7                        0/1     Completed   0             3m33s
portal-registration-7687ddc5cb-2v48p                          1/1     Running     0             78d
portal-registration-service-7956bcdd5-8tv4h                   1/1     Running     0             78d
portal-selfdescription-86cdcdbb8d-kt6vj                       1/1     Running     0             78d
portal-services-service-785d8c7d7f-n2bhb                      1/1     Running     0             78d
portal-sharedidp-0                                            1/1     Running     0             78d
portal-sharedidp-postgresql-0                                 1/1     Running     0             78d
portal-ssi-credential-issuer-66546bc477-lmkn7                 1/1     Running     0             78d
portal-ssi-credential-issuer-expiry-29845440-p2rf4            0/1     Completed   0             2d10h
portal-ssi-credential-issuer-expiry-29846880-nqhdn            0/1     Completed   0             34h
portal-ssi-credential-issuer-expiry-29848320-jt9pw            0/1     Completed   0             10h
portal-ssi-credential-issuer-processesworker-29848965-ggmdg   0/1     Completed   0             13m
portal-ssi-credential-issuer-processesworker-29848970-k4b4c   0/1     Completed   0             8m33s
portal-ssi-credential-issuer-processesworker-29848975-9wgqh   0/1     Completed   0             3m33s
smtp4dev-d6b588d5b-bpj2p                                      1/1     Running     0             78d
ssi-dim-wallet-stub-66b8748f-bhsl4                            1/1     Running     0             72d
wallet-postgres-0                                             1/1     Running     0             78d
```

```bash
kubectl get jobs -n portal
```

```text
NAME                                                    STATUS     COMPLETIONS   DURATION   AGE
bdrs-manual-seeding                                     Complete   1/1           5s         237d
bdrs-manual-seeding-v2                                  Complete   1/1           7s         141d
bdrs-manual-seeding-v3                                  Complete   1/1           6s         77d
bdrs-reseed-fixed                                       Complete   1/1           5s         197d
bdrs-reseed-fixed-v2                                    Complete   1/1           6s         141d
fix-https-requirement                                   Complete   1/1           5s         234d
fix-keycloak-urls-complete                              Complete   1/1           8s         234d
portal-centralidp-realm-seeding-10                      Complete   1/1           62s        238d
portal-centralidp-realm-seeding-13                      Complete   1/1           83s        234d
portal-centralidp-realm-seeding-8                       Complete   1/1           66s        238d
portal-portal-maintenance-29845440                      Complete   1/1           74s        2d10h
portal-portal-maintenance-29846880                      Complete   1/1           72s        34h
portal-portal-maintenance-29848320                      Complete   1/1           75s        10h
portal-portal-migrations                                Complete   1/1           36s        234d
portal-processes-worker-29736105                        Failed     0/1           78d        78d
portal-processes-worker-29848965                        Complete   1/1           47s        13m
portal-processes-worker-29848970                        Complete   1/1           47s        8m53s
portal-processes-worker-29848975                        Complete   1/1           47s        3m53s
portal-provisioning-migrations                          Complete   1/1           27s        234d
portal-sharedidp-realm-seeding-10                       Complete   1/1           19s        238d
portal-sharedidp-realm-seeding-13                       Complete   1/1           25s        234d
portal-sharedidp-realm-seeding-8                        Complete   1/1           19s        238d
portal-ssi-credential-issuer-expiry-29845440            Complete   1/1           68s        2d10h
portal-ssi-credential-issuer-expiry-29846880            Complete   1/1           69s        34h
portal-ssi-credential-issuer-expiry-29848320            Complete   1/1           76s        10h
portal-ssi-credential-issuer-migrations                 Complete   1/1           79s        234d
portal-ssi-credential-issuer-processesworker-29736105   Failed     0/1           78d        78d
portal-ssi-credential-issuer-processesworker-29848965   Complete   1/1           77s        13m
portal-ssi-credential-issuer-processesworker-29848970   Complete   1/1           75s        8m53s
portal-ssi-credential-issuer-processesworker-29848975   Complete   1/1           79s        3m53s
```

La captura incluye dos jobs antiguos en estado `Failed`, ambos con 78 dias de antiguedad. Se conserva su estado real; las ejecuciones posteriores mostradas de esos workers estan en estado `Complete`.

```bash
kubectl get ingress -n portal
```

```text
NAME                                          CLASS   HOSTS                                           ADDRESS        PORTS   AGE
bdrs-server-bdrs-server.51.178.94.25.nip.io   nginx   bdrs-server.51.178.94.25.nip.io                  51.178.94.25   80      241d
portal-bpdm-gate                              nginx   business-partners.51.178.94.25.nip.io            51.178.94.25   80      241d
portal-bpdm-orchestrator                      nginx   business-partners.51.178.94.25.nip.io            51.178.94.25   80      241d
portal-bpdm-pool                              nginx   business-partners.51.178.94.25.nip.io            51.178.94.25   80      241d
portal-centralidp                             nginx   centralidp.51.178.94.25.nip.io                   51.178.94.25   80      241d
portal-frontend                               nginx   portal.51.178.94.25.nip.io                       51.178.94.25   80      241d
portal-pgadmin4                               nginx   pgadmin4.51.178.94.25.nip.io                     51.178.94.25   80      241d
portal-portal-backend                         nginx   portal-backend.51.178.94.25.nip.io               51.178.94.25   80      241d
portal-selfdescription                        nginx   sdfactory.51.178.94.25.nip.io                    51.178.94.25   80      241d
portal-sharedidp                              nginx   sharedidp.51.178.94.25.nip.io                    51.178.94.25   80      241d
portal-ssi-credential-issuer                  nginx   ssi-credential-issuer.51.178.94.25.nip.io        51.178.94.25   80      241d
smtp4dev-ingress                              nginx   smtp4dev.51.178.94.25.nip.io                     51.178.94.25   80      241d
ssi-dim-wallet-ingress                        nginx   ssi-dim-wallet-stub.51.178.94.25.nip.io          51.178.94.25   80      238d
```

Se utiliza `umbrella` como nombre de release para coincidir con el despliegue actual; las primeras guias empleaban `portal`. Antes de actualizar un entorno existente, comprobar su release con `helm list -n portal` y conservar los valores aplicados, en especial persistencia, credenciales y servicios habilitados. No ejecutar una actualizacion con un perfil base sin revisar esas diferencias.

El despliegue utiliza [charts/umbrella/values-adopter-portal-for-onboarding-with-persistence.yaml](charts/umbrella/values-adopter-portal-for-onboarding-with-persistence.yaml) para habilitar el onboarding y la persistencia, y [charts/umbrella/values-ovh-hosts-portal.yaml](charts/umbrella/values-ovh-hosts-portal.yaml) para establecer las URLs de los hosts de OVH. Tractus-X y todos sus servicios centrales se instalan en el namespace `portal`; despues se despliegan los conectores EDC en el namespace `umbrella`. Completar las correcciones de URLs descritas mas abajo antes de validar el login del Portal.

## Partners y despliegue de conectores EDC

Este proyecto incluye el despliegue de los conectores de los siguientes partners:

| Partner | Identificador | Release Helm | Script de despliegue |
| --- | --- | --- | --- |
| Mondragon Assembly | MASS | `mass-edc` | [scripts/connector-deployment/deploy-mass-connector.sh](scripts/connector-deployment/deploy-mass-connector.sh) |
| Ikerlan | IKLN | `ikln-edc` | [scripts/connector-deployment/deploy-ikln-connector.sh](scripts/connector-deployment/deploy-ikln-connector.sh) |
| PartnerA (participante de prueba) | PRTA | `prta-edc` | [scripts/connector-deployment/deploy-prta-connector.sh](scripts/connector-deployment/deploy-prta-connector.sh) |

El despliegue de cada conector comprende **tres pasos**, detallados a continuacion:

1. Ejecutar el script de despliegue del partner.
2. Configurar los secretos de Vault del conector.
3. Actualizar el seeding de los partners en BDRS.

**Una vez desplegado y configurado, el conector debe registrarse a traves del Portal del espacio de datos para completar su puesta en servicio.** Cada partner debe realizar este registro con su cuenta en el Portal, indicando la URL HTTPS de su conector. Más detalles en [Detalles sobre el registro del conector a través del Portal](#detalles-sobre-el-registro-del-conector-a-trav%C3%A9s-del-portal).

### Paso 1. Ejecutar el script :

Desde la carpeta raiz ejecutar el script correpondiente para el conector del partner.

```bash
bash scripts/connector-deployment/deploy-mass-connector.sh
bash scripts/connector-deployment/deploy-ikln-connector.sh
bash scripts/connector-deployment/deploy-prta-connector.sh
```

Cada script ejecuta `helm upgrade --install` con el chart [charts/dataspace-connector-bundle](charts/dataspace-connector-bundle) y los valores especificos de su partner, espera al despliegue y muestra pods, servicios e ingress del namespace `umbrella`.

Antes de ejecutarlos, revisar la ruta de `KUBECONFIG` fijada dentro de los scripts y los ficheros de valores que referencian. Estos valores deben contener los BPN, URLs, configuracion de identidad y secretos adecuados. El Portal y los servicios de identidad deben estar operativos, y los certificados y secretos requeridos deben estar preparados. No utilizar la eliminacion del namespace como procedimiento para retirar un unico conector, ya que los tres lo comparten.

### Paso 2. Configurar los secretos de Vault

Ademas del despliegue Helm, hay que ejecutar el script de configuracion de secretos del partner correspondiente, una vez disponible su Vault en el namespace `umbrella`. Desde la raiz del repositorio, el orden es MASS, IKLN y PRTA:

```bash
bash scripts/connector-deployment/fix-mass-connector-vaults.sh
bash scripts/connector-deployment/fix-ikln-connector-vaults.sh
bash scripts/connector-deployment/fix-prta-connector-vaults.sh
```

Los scripts [scripts/connector-deployment/fix-mass-connector-vaults.sh](scripts/connector-deployment/fix-mass-connector-vaults.sh), [scripts/connector-deployment/fix-ikln-connector-vaults.sh](scripts/connector-deployment/fix-ikln-connector-vaults.sh) y [scripts/connector-deployment/fix-prta-connector-vaults.sh](scripts/connector-deployment/fix-prta-connector-vaults.sh) cargan los secretos que la configuracion de los conectores referencia por alias. Desplegar los pods con Helm no sustituye esta carga: si los secretos no existen, el conector no puede resolver las credenciales y claves necesarias para sus funciones de identidad y transferencia.

- `edc-wallet-secret`: secreto del cliente OAuth utilizado para acceder al servicio de tokens del wallet.
- `tokenSignerPrivateKey`: clave privada para la firma de tokens de transferencia.
- `tokenSignerPublicKey`: clave publica para verificar esos tokens.
- `tokenEncryptionAesKey`: clave AES para el cifrado de tokens de transferencia.

Cada script escribe estos cuatro secretos mediante `vault kv put` en el Vault propio del conector y termina con `vault kv list secret` para comprobar que aparecen sus nombres. Esa comprobacion no valida que los valores sean credenciales o claves correctas.

**Importante:** los scripts actuales escriben `changeme` como contenido de los cuatro secretos. Son valores de prueba, no claves criptograficas validas ni credenciales de produccion. Antes de ejecutarlos, revisar la ruta de `KUBECONFIG` y configurar valores adecuados y coherentes con el wallet y el conector. No ejecutarlos sobre un Vault ya configurado sin revisar su contenido, porque pueden sobrescribir secretos existentes. Estos scripts cargan secretos; no inicializan ni desbloquean un Vault sellado.

### Paso 3. Actualizar el seeding de los partners en BDRS

En [custom/jobs](custom/jobs) hay varios Jobs de Kubernetes para actualizar el seeding de los partners en **BDRS (BPN/DID Resolution Service)**. Registran la asociacion entre el BPN del participante y su DID mediante peticiones POST a `/api/management/bpn-directory` del servicio `bdrs-server`, en el namespace `portal`.

Este paso es necesario para que BDRS conozca los BPN de los partners incorporados al espacio de datos y pueda resolver su correspondencia con los DIDs usados por los conectores en los flujos de identidad y confianza. Desplegar un conector no registra automaticamente esa asociacion en BDRS. Si falta o apunta a un dominio antiguo, la resolucion de identidad puede fallar. Estos jobs **no generan ni asignan un BPN nuevo**: registran BPN ya definidos y tampoco sustituyen el registro del conector en el Portal ni la configuracion del wallet.

Los partners con conectores documentados aqui son, en este orden, MASS (`BPNL00000000MASS`), IKLN (`BPNL00000002IKLN`) y PRTA (`BPNL00000003PRTA`). Sus DIDs siguen el patron `did:web:ssi-dim-wallet-stub.51.178.94.25.nip.io:<BPN>`.

| Manifiesto | Contenido |
| --- | --- |
| [custom/jobs/bdrs-manual-seeding-v2.yaml](custom/jobs/bdrs-manual-seeding-v2.yaml) | Version historica para MASS, IKLN, el operador y participantes iniciales. Revisar el script embebido antes de reutilizarlo. |
| [custom/jobs/bdrs-manual-seeding-v3.yaml](custom/jobs/bdrs-manual-seeding-v3.yaml) | Amplia la lista anterior con PRTA y PRTB; es el ejemplo utilizado a continuacion. Incluir un BPN en este job no implica que su conector este desplegado. |
| [custom/jobs/bdrs-reseed-fixed-v2.yaml](custom/jobs/bdrs-reseed-fixed-v2.yaml) | Peticiones explicitas para registrar MASS, IKLN, el operador y participantes iniciales. |
| [custom/jobs/bdrs-reseed-fixed-v3.yaml](custom/jobs/bdrs-reseed-fixed-v3.yaml) | Variante con otro nombre de Job; actualmente contiene los mismos BPN que el reseeding v2, sin PRTA ni PRTB. |

**Varios jobs ya se han ejecutado.** En la consulta del cluster del **2026-10-02** constan con una ejecucion completada `bdrs-manual-seeding`, `bdrs-manual-seeding-v2`, `bdrs-manual-seeding-v3`, `bdrs-reseed-fixed` y `bdrs-reseed-fixed-v2`. Algunos son versiones historicas cuyo manifiesto ya no esta en este directorio. La existencia del manifiesto de reseeding v3 en el repositorio no demuestra que se haya ejecutado: no aparece entre los Jobs consultados.

#### Ejecutar un job por primera vez

Antes de ejecutarlo, revisar la lista de BPN, los DIDs, el dominio del wallet, la disponibilidad de BDRS y la clave de acceso a su API. Los manifiestos usan una clave de prueba; adaptar las credenciales al entorno. Desde la raiz del repositorio, con `KUBECONFIG` configurado y siempre que no exista ya un Job con ese nombre:

```bash
kubectl apply -n portal -f custom/jobs/bdrs-manual-seeding-v3.yaml
kubectl wait -n portal --for=condition=complete \
  job/bdrs-manual-seeding-v3 --timeout=300s
kubectl logs -n portal job/bdrs-manual-seeding-v3
```

Comprobar las respuestas de cada peticion en los logs. Un Job completado no basta por si solo para garantizar que todas las asociaciones se hayan registrado correctamente; revisar los errores HTTP y comprobar las entradas en BDRS. No asumir que repetir las peticiones POST sea inocuo para registros ya existentes sin comprobar el comportamiento de la API.

#### Volver a ejecutar un job existente

**Si ya existe un Job con el mismo `metadata.name`, hay que eliminarlo y recrearlo para volver a ejecutarlo.** Repetir `kubectl apply` sobre un Job completado no lanza otra ejecucion. Ademas, cambiar el script o la lista de BPN modifica la plantilla del pod, que normalmente es inmutable en un Job existente.

Primero consultar su estado y guardar los logs necesarios: al eliminar el Job tambien se eliminan normalmente sus pods y se pierde ese historial de logs. No borrar un Job que siga activo sin revisar antes la ejecucion en curso.

```bash
kubectl get job -n portal bdrs-manual-seeding-v3
kubectl logs -n portal job/bdrs-manual-seeding-v3
```

Una vez revisado el estado, para relanzar ese mismo job:

```bash
kubectl delete job -n portal bdrs-manual-seeding-v3 \
  --ignore-not-found=true --wait=true
kubectl apply -n portal -f custom/jobs/bdrs-manual-seeding-v3.yaml
kubectl wait -n portal --for=condition=complete \
  job/bdrs-manual-seeding-v3 --timeout=300s
kubectl logs -n portal job/bdrs-manual-seeding-v3
```

**No es necesario eliminar un job anterior con un nombre diferente.** Por ejemplo, el job manual v2 puede conservarse al ejecutar el manual v3. Tambien se puede usar un nombre nuevo en `metadata.name` para conservar el historial de la ejecucion anterior; evitar ejecuciones simultaneas sobre los mismos registros.

### Registro y comprobacion en el Portal

Desplegar el EDC no equivale a registrar su URL en el Portal. El procedimiento normal es el registro a traves del Portal y la comprobacion de su activacion tras generar la autodescripcion. Como herramienta de mantenimiento, para registrar o corregir directamente en base de datos la URL DSP asociada al BPN del partner se dispone de [scripts/partner/register-partner-connector-in-db.sh](scripts/partner/register-partner-connector-in-db.sh); este script no sustituye el flujo normal de registro y autodescripcion del Portal. Primero revisar la simulacion (`--dry-run`) y despues aplicar (`--apply`). Ejemplo para Mondragon Assembly (MASS):

```bash
bash scripts/partner/register-partner-connector-in-db.sh \
  BPNL00000000MASS \
  https://edc-mass-control.51.178.94.25.nip.io/api/v1/dsp --dry-run
bash scripts/partner/register-partner-connector-in-db.sh \
  BPNL00000000MASS \
  https://edc-mass-control.51.178.94.25.nip.io/api/v1/dsp --apply
bash scripts/partner/check-in-db-partner-registration-and-connector.sh BPNL00000000MASS
```

La comprobacion [scripts/partner/check-in-db-partner-registration-and-connector.sh](scripts/partner/check-in-db-partner-registration-and-connector.sh) revisa la compania, los usuarios y la URL del conector. Usar el BPN y la URL DSP correspondientes al registrar los demas partners.

## Correcciones posteriores al despliegue de Tractus-X en OVH

La configuracion original de Tractus-X utiliza el sufijo **`tx.test`** (no `tx.text`). Este espacio de datos utiliza **`51.178.94.25.nip.io`**. Tras desplegar Tractus-X fue necesario corregir directamente las bases de datos de Keycloak, porque el seeding de los realms no actualiza todos los registros existentes aunque se cambien los valores Helm.

Las correcciones afectan a las bases `iamcentralidp` y `iamsharedidp`: URL base de clientes (`client.root_url`), redirecciones OAuth (`redirect_uris`), endpoints de federacion de `CX-Operator` (`identity_provider_config`) y URL de claves publicas JWKS (`client_attributes`). Sin estas correcciones, el login puede fallar por redirecciones invalidas o por intentar acceder a hosts `tx.test`.

### Scripts y jobs de correccion

| Utilidad | Finalidad |
| --- | --- |
| [charts/umbrella/fix-keycloak-urls.sh](charts/umbrella/fix-keycloak-urls.sh) | Correccion SQL directamente en los PostgreSQL de CentralIDP y SharedIDP mediante `kubectl exec`; recibe `EXTERNAL_IP` y `DNS_SUFFIX`. |
| [charts/umbrella/fix-keycloak-urls-job-complete.yaml](charts/umbrella/fix-keycloak-urls-job-complete.yaml) | Alternativa utilizada para ejecutar las correcciones SQL como Job de Kubernetes. Revisar las variables de IP y sufijo antes de aplicarlo. |
| [fix-centralidp-redirect-uri.sh](fix-centralidp-redirect-uri.sh) | Correccion complementaria de las redirecciones del cliente `central-idp` en los realms del SharedIDP mediante la administracion de Keycloak. |
| [fix-centralidp-https.sh](fix-centralidp-https.sh) y [fix-realm-https.sh](fix-realm-https.sh) | Ajustes complementarios del requisito SSL para el acceso HTTP de este entorno; no sustituyen la correccion de dominios en SQL. |
| [fix-https-idp-realms.sh](fix-https-idp-realms.sh) | Ajuste del requisito SSL en los realms del SharedIDP para este entorno HTTP, con comprobacion final del valor configurado. |

Realizar una copia de seguridad antes de modificar las bases de datos. No ejecutar indiscriminadamente todos los scripts: elegir la correccion necesaria y revisar IPs, rutas y credenciales. Los ajustes que desactivan la exigencia de HTTPS son especificos de este entorno y no son una configuracion recomendada para produccion.

Ejemplo de correccion SQL, desde la raiz del repositorio:

```bash
export EXTERNAL_IP="51.178.94.25"
export DNS_SUFFIX="nip.io"
bash charts/umbrella/check-keycloak-urls.sh
bash charts/umbrella/fix-keycloak-urls.sh

kubectl delete pod -n portal -l app.kubernetes.io/name=centralidp
kubectl delete pod -n portal -l app.kubernetes.io/name=sharedidp
kubectl wait --for=condition=Ready pod -n portal \
  -l app.kubernetes.io/name=centralidp --timeout=300s
kubectl wait --for=condition=Ready pod -n portal \
  -l app.kubernetes.io/name=sharedidp --timeout=300s

bash charts/umbrella/check-keycloak-urls.sh
```

Como alternativa al script de correccion, aplicar el Job y consultar su resultado:

```bash
kubectl apply -n portal -f charts/umbrella/fix-keycloak-urls-job-complete.yaml
kubectl wait -n portal --for=condition=complete \
  job/fix-keycloak-urls-complete --timeout=300s
kubectl logs -n portal job/fix-keycloak-urls-complete
```

Despues del Job tambien es necesario reiniciar Keycloak y volver a comprobar las URLs. El reinicio permite recargar los cambios guardados en la base de datos.

### Comprobacion de las correcciones

| Utilidad | Que comprueba |
| --- | --- |
| [charts/umbrella/check-keycloak-urls.sh](charts/umbrella/check-keycloak-urls.sh) | Consultas SQL en ambas bases de datos, deteccion de referencias a `tx.test` y resumen de los dominios configurados. Ejecutar antes y despues de corregir. |
| [charts/umbrella/check-keycloak-urls-job.yaml](charts/umbrella/check-keycloak-urls-job.yaml) | Comprobacion acotada de redirecciones con `tx.test` en CentralIDP mediante un Job. |
| [charts/umbrella/check-new-realm.sh](charts/umbrella/check-new-realm.sh) | Inspeccion de un realm del SharedIDP y sus clientes; complemento para problemas de federacion tras crear un nuevo realm. |

Revisar que las URLs necesarias ya no apunten a `tx.test` ni a IPs antiguas, y que usen `51.178.94.25.nip.io` con el protocolo previsto. El indicador `OK` del script detecta la ausencia de `tx.test`, pero por si solo no garantiza que la IP sea la correcta. Por ultimo, probar el login del Portal en una ventana privada o tras limpiar las cookies del dominio.

Otras adaptaciones de hosts e ingress se recogen en [charts/umbrella/fix-bpdm-hosts.sh](charts/umbrella/fix-bpdm-hosts.sh), [fix-bpdm-ingress-ovh.sh](fix-bpdm-ingress-ovh.sh) y [fix-selfdescription-ingress-ovh.sh](fix-selfdescription-ingress-ovh.sh). No son correcciones SQL de Keycloak; algunas conservan IPs historicas que deben actualizarse antes de ejecutarlas.

## Aclaraciones sobre los valores de hosts de OVH

Inicialmente se creo el script [charts/umbrella/generate_file_values_ovh_hosts_portal.sh](charts/umbrella/generate_file_values_ovh_hosts_portal.sh) para generar el manifiesto [charts/umbrella/values-ovh-hosts-portal.yaml](charts/umbrella/values-ovh-hosts-portal.yaml) a partir de [charts/umbrella/values-ovh-hosts-portal-template.yaml](charts/umbrella/values-ovh-hosts-portal-template.yaml), incorporando el sufijo correcto `51.178.94.25.nip.io` en las URLs. Este es el proceso descrito en [charts/umbrella/README-deployment.md](charts/umbrella/README-deployment.md).

Finalmente no se utilizo ese script para el despliegue: el manifiesto de valores que establece las URLs de los hosts de OVH se implemento directamente en [charts/umbrella/values-ovh-hosts-portal.yaml](charts/umbrella/values-ovh-hosts-portal.yaml). Por tanto, el despliegue documentado utiliza este manifiesto junto con el perfil de onboarding con persistencia, sin depender de la generacion desde plantilla. No regenerar el manifiesto sin revisar los cambios, ya que se podria sobrescribir la configuracion incorporada directamente.

## Detalles sobre el registro del conector a través del Portal

La guia [dokumentuak/2026.02.05 - Despliegue Conectores EDC con TLS y Registro en Portal.md](dokumentuak/2026.02.05%20-%20Despliegue%20Conectores%20EDC%20con%20TLS%20y%20Registro%20en%20Portal.md) explica el motivo: el registro normal crea el conector en estado `PENDING`, inicia el proceso `SELF_DESCRIPTION_CREATION` y solicita su autodescripcion a SD Factory. Cuando se recibe el documento, el conector pasa a `ACTIVE`. La guia documenta que el alta directa en base de datos, al saltarse este proceso, dejo conectores en `PENDING` sin activacion automatica. Por tanto, desplegar el EDC y registrar su BPN en BDRS no sustituye el registro y la activacion en el Portal.

Si se omite el registro, la comprobacion [scripts/partner/check-in-db-partner-registration-and-connector.sh](scripts/partner/check-in-db-partner-registration-and-connector.sh) muestra el diagnostico `Existe company, pero no hay registro en portal.connectors` y termina con codigo de salida **3**. Si hay un registro pero falta su URL, muestra `Hay connectors, pero connector_url esta vacio` y termina con codigo **4**. Son diagnosticos del script de comprobacion, no mensajes del runtime EDC; la documentacion consultada no identifica un unico error del EDC causado exclusivamente por omitir el registro. Ademas, estos diagnosticos no comprueban la autodescripcion ni garantizan el estado `ACTIVE`.

## Documentacion adicional

- [dokumentuak/2026.01.16 - Portal-deployment-in-ovh.md](dokumentuak/2026.01.16%20-%20Portal-deployment-in-ovh.md): procedimiento detallado y correcciones de URLs; contiene IPs de despliegues anteriores.
- [historial_despliegue_ovh.md](historial_despliegue_ovh.md): historial inicial del despliegue y diagnostico de las incidencias de Keycloak.
- [docs](docs): documentacion tecnica heredada del proyecto Tractus-X Umbrella.

## Contribuciones y licencia

Consultar [CONTRIBUTING.md](CONTRIBUTING.md) para las pautas de contribucion. El codigo se distribuye bajo Apache 2.0; consultar [LICENSE](LICENSE) y [NOTICE.md](NOTICE.md). Para el material no relacionado con codigo, consultar [LICENSE_non-code](LICENSE_non-code).
