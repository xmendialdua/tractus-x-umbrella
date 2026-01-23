# 1. Definición de variables
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

# 4. El Grupo de Nodos: "tractus-x-umbrella"
resource "ovh_cloud_project_kube_nodepool" "node_pool" {
  service_name  = var.ovh_service_name
  kube_id       = ovh_cloud_project_kube.my_kube_cluster.id
  name          = "tractus-x-umbrella"  # Nombre del pool
  flavor_name   = "b2-7"     # Tipo de nodo B2-7 (Propósito General)
  desired_nodes = 3      # 3 nodos para el portal
  max_nodes     = 3
  min_nodes     = 3
}

# 5. Generar automáticamente el archivo kubeconfig.yaml
resource "local_file" "kubeconfig" {
  content  = ovh_cloud_project_kube.my_kube_cluster.kubeconfig
  filename = "${path.module}/../kubeconfig.yaml"
  file_permission = "0600"
}

# 6. Extraer el archivo Kubeconfig automáticamente para conectar desde VS Code
output "kubeconfig_data" {
  value     = ovh_cloud_project_kube.my_kube_cluster.kubeconfig
  sensitive = true
}

# 7. Obtener el ID del cluster
output "cluster_id" {
  value       = ovh_cloud_project_kube.my_kube_cluster.id
  description = "ID único del cluster (ej: cul9qm)"
}

# 8. Obtener la URL del cluster
output "cluster_url" {
  value       = ovh_cloud_project_kube.my_kube_cluster.url
  description = "URL completa del API Server"
}

# 9. Obtener información completa del cluster
output "cluster_info" {
  value = {
    id      = ovh_cloud_project_kube.my_kube_cluster.id
    name    = ovh_cloud_project_kube.my_kube_cluster.name
    region  = ovh_cloud_project_kube.my_kube_cluster.region
    version = ovh_cloud_project_kube.my_kube_cluster.version
    url     = ovh_cloud_project_kube.my_kube_cluster.url
    status  = ovh_cloud_project_kube.my_kube_cluster.status
  }
}