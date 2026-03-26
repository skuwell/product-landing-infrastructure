# Google Cloud APIs Module
# Enables required Google Cloud APIs for the grading application

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

# Enable Vision API
resource "google_project_service" "vision_api" {
  project = var.project_id
  service = "vision.googleapis.com"

  disable_on_destroy = false
  disable_dependent_services = false
}

# Enable Cloud Resource Manager API (required for IAM)
resource "google_project_service" "cloudresourcemanager_api" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"

  disable_on_destroy = false
  disable_dependent_services = false
}

# Enable IAM API
resource "google_project_service" "iam_api" {
  project = var.project_id
  service = "iam.googleapis.com"

  disable_on_destroy = false
  disable_dependent_services = false
}

# Enable Service Usage API
resource "google_project_service" "serviceusage_api" {
  project = var.project_id
  service = "serviceusage.googleapis.com"

  disable_on_destroy = false
  disable_dependent_services = false
}

# Service Account for Vision API access
resource "google_service_account" "vision_api_sa" {
  account_id   = "grading-app-vision"
  display_name = "Grading App Vision API Service Account"
  description  = "Service account for Vision API access from grading application"
  project      = var.project_id

  depends_on = [google_project_service.iam_api]
}

# Note: IAM role binding requires project-level IAM admin permissions
# If you get permission denied, manually grant roles using gcloud:
#
# gcloud projects add-iam-policy-binding PROJECT_ID \
#   --member="serviceAccount:grading-app-vision@PROJECT_ID.iam.gserviceaccount.com" \
#   --role="roles/ml.developer"
#
# Or attach the service account directly to the VM (recommended):
# The VM's existing service account already has necessary permissions

# Create service account key (for application authentication)
resource "google_service_account_key" "vision_api_key" {
  service_account_id = google_service_account.vision_api_sa.name
  
  depends_on = [google_service_account.vision_api_sa]
}

# Store the service account key in a local file
# NOTE: In production, use Secret Manager instead
resource "local_file" "vision_api_credentials" {
  count    = var.store_credentials_locally ? 1 : 0
  content  = base64decode(google_service_account_key.vision_api_key.private_key)
  filename = "${path.root}/credentials/vision-api-credentials.json"
  
  file_permission = "0600"
}
