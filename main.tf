# Product Landing Environment

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# Enable required APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "required_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com",
    "storage-api.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
module "networking" {
  source = "./modules/networking"

  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  vpc_name      = var.vpc_name
  subnet_cidr   = var.subnet_cidr
  enable_cloud_nat = var.enable_cloud_nat

  allowed_ssh_cidr_ranges  = var.allowed_ssh_cidr_ranges
  allowed_http_cidr_ranges = var.allowed_http_cidr_ranges

  depends_on = [google_project_service.required_apis]
}

# ---------------------------------------------------------------------------
# Security — Service accounts + base Secret Manager secrets
# ---------------------------------------------------------------------------
module "security" {
  source = "./modules/security"

  project_id  = var.project_id
  environment = var.environment
  app_name    = var.app_name

  depends_on = [google_project_service.required_apis]
}

# ---------------------------------------------------------------------------
# Additional Secret Manager secrets for product-landing-app
# ---------------------------------------------------------------------------
resource "google_secret_manager_secret" "jwt_private_key" {
  project   = var.project_id
  secret_id = "jwt-private-key-${var.environment}"

  replication { auto {} }
}

resource "google_secret_manager_secret_version" "jwt_private_key" {
  secret      = google_secret_manager_secret.jwt_private_key.id
  secret_data = var.jwt_private_key_pem
}

resource "google_secret_manager_secret_iam_member" "jwt_private_key_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_private_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.security.app_service_account_email}"
}

resource "google_secret_manager_secret" "jwt_public_key" {
  project   = var.project_id
  secret_id = "jwt-public-key-${var.environment}"

  replication { auto {} }
}

resource "google_secret_manager_secret_version" "jwt_public_key" {
  secret      = google_secret_manager_secret.jwt_public_key.id
  secret_data = var.jwt_public_key_pem
}

resource "google_secret_manager_secret_iam_member" "jwt_public_key_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.jwt_public_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.security.app_service_account_email}"
}

resource "google_secret_manager_secret" "db_password" {
  project   = var.project_id
  secret_id = "db-password-${var.environment}"

  replication { auto {} }
}

resource "random_password" "db_password" {
  length  = 32
  special = false # avoid shell-quoting issues in startup script
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}

resource "google_secret_manager_secret_iam_member" "db_password_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.db_password.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${module.security.app_service_account_email}"
}

# ---------------------------------------------------------------------------
# Storage — GCS buckets (uploads + backups + terraform-state)
# ---------------------------------------------------------------------------
module "storage" {
  source = "./modules/storage"

  project_id         = var.project_id
  region             = var.region
  environment        = var.environment
  bucket_name_prefix = "${var.project_id}-${var.app_name}"
  location           = var.bucket_location
  storage_class      = var.bucket_storage_class

  depends_on = [google_project_service.required_apis]
}

# Grant the VM service account write access to the backups bucket
resource "google_storage_bucket_iam_member" "backups_write" {
  bucket = module.storage.backups_bucket_name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.security.app_service_account_email}"
}

# ---------------------------------------------------------------------------
# Cloud SQL (PostgreSQL 16)  — production database with automated backups
# ---------------------------------------------------------------------------
module "database" {
  source = "./modules/database"

  project_id        = var.project_id
  region            = var.region
  environment       = var.environment
  instance_name     = "${var.app_name}-db"
  database_version  = var.db_version
  tier              = var.db_tier
  disk_size_gb      = var.db_disk_size_gb
  backup_enabled    = true
  ha_enabled        = var.db_ha_enabled
  network_self_link = module.networking.network_self_link

  depends_on = [google_project_service.required_apis, module.networking]
}

# ---------------------------------------------------------------------------
# Compute — single VM, startup script deploys product-landing-app via Docker
# ---------------------------------------------------------------------------
module "compute" {
  source = "./modules/compute"

  project_id    = var.project_id
  region        = var.region
  zone          = var.zone
  environment   = var.environment
  instance_name = "${var.app_name}-vm"
  machine_type  = var.vm_machine_type
  disk_size_gb  = var.vm_disk_size_gb
  image_family  = var.vm_image_family
  image_project = var.vm_image_project
  network_name  = module.networking.network_name
  subnet_name   = module.networking.subnet_name

  service_account_email    = module.security.app_service_account_email
  enable_security_hardening = true

  startup_script = templatefile("${path.module}/startup-script.sh", {
    project_id          = var.project_id
    environment         = var.environment
    app_name            = var.app_name
    app_repo_url        = var.app_repo_url
    app_repo_branch     = var.app_repo_branch
    domain              = var.domain
    certbot_email       = var.certbot_email
    db_connection_name  = module.database.instance_connection_name
    db_name             = var.db_name
    db_user             = var.db_user
    backups_bucket      = module.storage.backups_bucket_name
    allowed_origins     = var.allowed_origins
  })

  depends_on = [
    google_project_service.required_apis,
    module.networking,
    module.security,
    module.database,
  ]
}
