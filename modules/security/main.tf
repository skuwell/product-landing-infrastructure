# Service Account for Application
resource "google_service_account" "app_sa" {
  account_id   = "${var.app_name}-sa-${var.environment}"
  display_name = "Service Account for ${var.app_name} (${var.environment})"
  project      = var.project_id
}

# Service Account for Terraform
resource "google_service_account" "terraform_sa" {
  account_id   = "${var.app_name}-terraform-sa"
  display_name = "Service Account for Terraform"
  project      = var.project_id
}

# IAM Roles for Application Service Account
# Note: Assign these roles manually via gcloud:
# gcloud projects add-iam-policy-binding wide-pulsar-477716-p4 \
#   --member="serviceAccount:grading-app-sa-dev@wide-pulsar-477716-p4.iam.gserviceaccount.com" \
#   --role="roles/cloudsql.client"
# ... (repeat for other roles)

# Commented out to avoid permission errors - assign manually instead
# resource "google_project_iam_member" "app_sa_roles" {
#   for_each = toset([
#     "roles/cloudsql.client",
#     "roles/storage.objectAdmin",
#     "roles/secretmanager.secretAccessor",
#     "roles/logging.logWriter",
#     "roles/monitoring.metricWriter",
#   ])
#   
#   project = var.project_id
#   role    = each.value
#   member  = "serviceAccount:${google_service_account.app_sa.email}"
# }

# IAM Roles for Terraform Service Account  
# Commented out to avoid permission errors - assign manually instead
# resource "google_project_iam_member" "terraform_sa_roles" {
#   for_each = toset([
#     "roles/compute.admin",
#     "roles/iam.serviceAccountAdmin",
#     "roles/storage.admin",
#     "roles/cloudsql.admin",
#     "roles/secretmanager.admin",
#     "roles/resourcemanager.projectIamAdmin"
#   ])
#   
#   project = var.project_id
#   role    = each.value
#   member  = "serviceAccount:${google_service_account.terraform_sa.email}"
# }

# Secret for Application Secret Key
resource "google_secret_manager_secret" "app_secret_key" {
  project   = var.project_id
  secret_id = "app-secret-key-${var.environment}"
  
  replication {
    auto {}
  }
}

resource "random_password" "app_secret_key" {
  length  = 64
  special = true
}

resource "google_secret_manager_secret_version" "app_secret_key" {
  secret      = google_secret_manager_secret.app_secret_key.id
  secret_data = random_password.app_secret_key.result
}

# Grant service account access to secrets
resource "google_secret_manager_secret_iam_member" "app_secret_access" {
  project   = var.project_id
  secret_id = google_secret_manager_secret.app_secret_key.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.app_sa.email}"
}
