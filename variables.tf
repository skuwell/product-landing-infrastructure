# === Project ===
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name used for resource naming"
  type        = string
  default     = "product-landing"
}

# === Networking ===
variable "vpc_name" {
  description = "Name of the VPC"
  type        = string
  default     = "product-landing-vpc"
}

variable "subnet_cidr" {
  description = "CIDR range for the subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for outbound traffic"
  type        = bool
  default     = true
}

variable "allowed_ssh_cidr_ranges" {
  description = "CIDR ranges allowed for SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidr_ranges" {
  description = "CIDR ranges allowed for HTTP/HTTPS"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# === Compute ===
variable "vm_machine_type" {
  description = "VM machine type — e2-standard-2 recommended for 7 containers"
  type        = string
  default     = "e2-standard-2"
}

variable "vm_disk_size_gb" {
  description = "VM boot disk size in GB"
  type        = number
  default     = 40
}

variable "vm_image_family" {
  description = "VM image family"
  type        = string
  default     = "ubuntu-2204-lts"
}

variable "vm_image_project" {
  description = "VM image project"
  type        = string
  default     = "ubuntu-os-cloud"
}

# === Database ===
variable "db_tier" {
  description = "Cloud SQL tier"
  type        = string
  default     = "db-g1-small"
}

variable "db_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "POSTGRES_16"
}

variable "db_disk_size_gb" {
  description = "Database disk size in GB"
  type        = number
  default     = 20
}

variable "db_ha_enabled" {
  description = "Enable Cloud SQL high availability (failover replica)"
  type        = bool
  default     = false
}

variable "db_name" {
  description = "Database name inside Cloud SQL"
  type        = string
  default     = "productlanding"
}

variable "db_user" {
  description = "Database user"
  type        = string
  default     = "app_user"
}

# === Storage ===
variable "bucket_location" {
  description = "Cloud Storage bucket location"
  type        = string
  default     = "US"
}

variable "bucket_storage_class" {
  description = "Cloud Storage class"
  type        = string
  default     = "STANDARD"
}

# === Application ===
variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
  default     = "product-landing"
}

variable "app_repo_url" {
  description = "GitHub repository URL for the product-landing-app"
  type        = string
  default     = "https://github.com/skuwell/product-landing-app.git"
}

variable "app_repo_branch" {
  description = "Git branch to deploy"
  type        = string
  default     = "main"
}

variable "domain" {
  description = "Domain name for Let's Encrypt TLS certificate (set to '' to skip certbot)"
  type        = string
  default     = ""
}

variable "certbot_email" {
  description = "Email address for Let's Encrypt registration"
  type        = string
  default     = ""
}

variable "allowed_origins" {
  description = "CORS allowed origins (comma-separated)"
  type        = string
  default     = ""
}

# === JWT keys (sensitive — provide via TF_VAR_* or terraform.tfvars) ===
variable "jwt_private_key_pem" {
  description = "RSA-2048 private key PEM for JWT signing (auth-service)"
  type        = string
  sensitive   = true
}

variable "jwt_public_key_pem" {
  description = "RSA-2048 public key PEM for JWT verification (all services)"
  type        = string
  sensitive   = true
}
