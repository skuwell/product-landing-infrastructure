# Uploads Bucket
resource "google_storage_bucket" "uploads" {
  name          = "${var.bucket_name_prefix}-uploads-${var.environment}"
  project       = var.project_id
  location      = var.location
  storage_class = var.storage_class
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = var.versioning_enabled
  }
  
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  
  lifecycle_rule {
    condition {
      age = var.lifecycle_age_days * 2
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  
  cors {
    origin          = ["*"]  # Update with actual domain
    method          = ["GET", "POST", "PUT", "DELETE"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
  
  labels = {
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "uploads"
  }
}

# Backups Bucket
resource "google_storage_bucket" "backups" {
  name          = "${var.bucket_name_prefix}-backups-${var.environment}"
  project       = var.project_id
  location      = var.location
  storage_class = "NEARLINE"  # Cheaper for backups
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      age = 30  # Delete backups older than 30 days
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    environment = var.environment
    managed_by  = "terraform"
    purpose     = "backups"
  }
}

# Terraform State Bucket (for remote state)
resource "google_storage_bucket" "terraform_state" {
  name          = "${var.bucket_name_prefix}-terraform-state"
  project       = var.project_id
  location      = var.location
  storage_class = "STANDARD"
  
  uniform_bucket_level_access = true
  
  versioning {
    enabled = true
  }
  
  lifecycle_rule {
    condition {
      num_newer_versions = 10
    }
    action {
      type = "Delete"
    }
  }
  
  labels = {
    managed_by = "terraform"
    purpose    = "terraform-state"
  }
}
