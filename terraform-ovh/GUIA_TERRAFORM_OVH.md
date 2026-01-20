# Guía de Despliegue de Tractus-X en OVH Cloud

Esta guía está diseñada para que un principiante pueda levantar un entorno de pruebas profesional, seguro y, sobre todo, fácil de destruir para controlar el gasto.

---

# 1. Instalación de Herramientas

Necesitamos tres piezas clave: Terraform (para la infraestructura), Kubectl (para gestionar los pods) y OpenStack CLI (opcional, pero útil para automatizar la descarga del archivo de configuración).

## 1.1 Instalar Terraform

Ejecuta estos comandos en tu terminal de VS Code:

```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install terraform
```

## 1.2 Instalar Kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
```

## 1.3 Instalar OpenStack CLI (Opcional pero Recomendado)

Para gestionar recursos de OVH desde la terminal:

```bash
sudo apt-get install python3-pip
pip3 install python-openstackclient
```

---

# 2. Configuración de Credenciales de OVH

Antes de usar Terraform, debes generar las llaves de acceso en la API de OVH:

1. Ve a: https://api.ovh.com/createToken/

2. Configura los permisos correctamente. 
  Rellena los campos:
   - GET/POST/PUT/DELETE para los endpoints: `/cloud/*` y `/order/*`
   - Validity: Unlimited (o el tiempo que prefieras)

    Asegúrate de marcar TODOS estos permisos:
    - GET    /cloud/*
    - POST   /cloud/*
    - PUT    /cloud/*
    - DELETE /cloud/*
    - GET    /order/*
    - POST   /order/*
    
      Importante: Marca todas las casillas (GET, POST, PUT, DELETE) para /cloud/*

    Configura la validez
      
        Validity: Unlimited (o el tiempo que necesites)

    Valores que he asignado:
      - Application name: tractus-x-umbrella-portal
      - Application description: Despliegue del Portal de Tractus-X
      - Validity: Unlimited
      - Rights
        - GET    /cloud/*
        - POST   /cloud/*
        - PUT    /cloud/*
        - DELETE /cloud/*
        - GET    /order/*
        - POST   /order/*
      
      Ya había creado antes con Application name tractus-x-umbrella y he tenido que cambiar el nombre.
      TODO: Ver como se puede eliminar el anterior.

      Las credenciales se pueden ver en: https://www.ovh.com/auth/api/credential
      


3. Genera un fichero terraform.tfvars, con el siguietne contenido

    - ovh_application_key    = "TU_NUEVA_APPLICATION_KEY"
    - ovh_application_secret = "TU_NUEVO_APPLICATION_SECRET"
    - ovh_consumer_key       = "TU_NUEVO_CONSUMER_KEY"
    - ovh_service_name       = "1628a7f46efb477f9f26ebdcdb2a3323"

4. Copia los tres valores: **Application Key**, **Application Secret** y **Consumer Key**

Otra alternativa. En tu terminal de VS Code, expórtalos (puedes pegarlo en tu archivo `~/.bashrc` para que sea permanente):

```bash
export OVH_ENDPOINT=ovh-eu
export OVH_APPLICATION_KEY="tu_key"
export OVH_APPLICATION_SECRET="tu_secret"
export OVH_CONSUMER_KEY="tu_consumer_key"
```

---

# 3. Creación del Cluster con Terraform

Crea una carpeta para tu proyecto y dentro un archivo llamado `main.tf`.

## 3.1 El archivo main.tf

Copia este contenido:

# 1. Definición de variables

```hcl

variable "ovh_application_key" {}
variable "ovh_application_secret" {}
variable "ovh_consumer_key" {}
variable "ovh_service_name" {
  default = "1628a7f46efb477f9f26ebdcdb2a3323" # Lo verás en el panel de Public Cloud como "Project ID"
}


terraform {
  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = ">= 0.13.0"
    }
  }
}

# 2. Configuración del Proveedor
provider "ovh" {
  endpoint           = "ovh-eu"
  application_key    = var.ovh_application_key
  application_secret = var.ovh_application_secret
  consumer_key       = var.ovh_consumer_key
}

# 3. El Cluster de Kubernetes: "dataspace" (Managed K8s)
resource "ovh_cloud_project_kube" "my_kube_cluster" {
  service_name = var.ovh_service_name
  name         = "dataspace"
  region       = "GRA5"      # Gravelines / GRA5
  version      = "1.34"      # Versión Kubernetes 1.34
  # Al no definir 'private_network_id', se crea sobre la red pública (Ninguna red privada)
}

# TODO: Más adelante actualizar desired nodes a 3, junto con max_nodes y min_nodes

# 4. El Grupo de Nodos: "tractus-x-umbrella"
resource "ovh_cloud_project_kube_nodepool" "node_pool" {
  service_name  = var.ovh_service_name
  kube_id       = ovh_cloud_project_kube.my_kube_cluster.id
  name          = "tractus-x-umbrella"  # Nombre del pool
  flavor_name   = "b2-7"     # Tipo de nodo B2-7 (Propósito General)
  desired_nodes = 1      # Empezamos con 1 solo nodo para aprender     # Actualizar más adelante a 3 nodos fijos
  max_nodes     = 2      # Actualizar más adelante a 3
  min_nodes     = 1      #   Actualizar más adelante a 3
}

# 5. Extraer el archivo Kubeconfig automáticamente para conectar desde VS Code
output "kubeconfig_data" {
  value     = ovh_cloud_project_kube.my_kube_cluster.kubeconfig
  sensitive = true
}
```

## 3.2 Crear archivo terraform.tfvars

Crea un archivo `terraform.tfvars` en la misma carpeta que `main.tf`:

```hcl
ovh_application_key    = "tu_application_key_aqui"
ovh_application_secret = "tu_application_secret_aqui"
ovh_consumer_key       = "tu_consumer_key_aqui"
ovh_service_name       = "1628a7f46efb477f9f26ebdcdb2a3323"  # Tu Project ID de OVH
```

ovh_service_name
  Es el identificador único de tu proyecto en OVH Cloud
  Lo encuentras en el panel de OVH como "Project ID"
  En nuestro caso: "1628a7f46efb477f9f26ebdcdb2a3323"

**Importante**: Añade este archivo a `.gitignore` para no subir credenciales:

```bash
echo "terraform.tfvars" >> .gitignore
```

## 3.2 Ejecución

1. **Inicializar**: `terraform init` (solo la primera vez)
2. **Planificar**: `terraform plan -out=tfplan`
3. **Verificar que `service_name` es tu Project ID** 
4. **Desplegar**: `terraform apply tfplan`

### Verificación del Plan Corregido

Después de aplicar la solución, ejecuta de nuevo `terraform plan` y verifica que muestre:

```
service_name = "1628a7f46efb477f9f26ebdcdb2a3323"  # Tu Project ID real
```

Para obtener el archivo de acceso:

```bash
terraform output -raw kubeconfig > kubeconfig.yaml
export KUBECONFIG=$PWD/kubeconfig.yaml
# Prueba que funciona:
kubectl get nodes
```

---

# 4. Eliminación de los recursos

Para asegurarte de que no quede nada facturando, sigue estos pasos en orden:

## 4.1 Paso 1: El comando de limpieza

Desde la carpeta donde tienes tu `main.tf`, ejecuta:

```bash
terraform destroy
```

Terraform detectará que creó un Cluster y un Nodepool y los borrará de forma ordenada.

## 4.2 Paso 2: Comprobación de seguridad

Para estar 100% seguro de que no hay costes fantasma:

### Vía CLI

Ejecuta este comando (requiere ovh-cli o simplemente verificar que el kubeconfig ya no conecta):

```bash
kubectl get nodes
# Debería dar un error de conexión o timeout.
```

### Comprobar Block Storage desde VS Code

Si instalaste OpenStack CLI, puedes verificar volúmenes sin salir de VS Code:

**Paso 1**: Descarga el archivo de configuración OpenStack desde OVH:
1. Ve a **Public Cloud > Users & Roles**
2. Descarga el archivo `openrc.sh`
3. Cárgalo en tu terminal:

```bash
source ~/ruta/a/openrc.sh
# Te pedirá la contraseña del usuario
```

**Paso 2**: Lista todos los volúmenes de Block Storage:

```bash
openstack volume list
```

**Paso 3**: Si hay volúmenes huérfanos (sin cluster asociado), elimínalos:

```bash
openstack volume delete <VOLUME_ID>
```

**Paso 4**: Verifica que no quedan Persistent Volume Claims:

```bash
kubectl get pvc --all-namespaces
# Si el cluster ya no existe, este comando fallará (lo cual es bueno)
```

### Vía Web (Recomendado al principio)

1. Ve a la sección **Public Cloud > Managed Kubernetes**. La lista debe estar vacía.
2. Ve a **Public Cloud > Instances**. Asegúrate de que no queden instancias vivas creadas por el cluster.

**Importante**: Revisa **Public Cloud > Block Storage**. A veces, si creaste volúmenes persistentes (PVC) en tus pruebas de Kubernetes, estos pueden quedarse ahí. Terraform debería borrarlos si los gestionó él, pero conviene echar un ojo.

---