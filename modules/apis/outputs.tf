# Outputs for Google Cloud APIs Module

output "vision_api_enabled" {
  description = "Whether Vision API is enabled"
  value       = google_project_service.vision_api.service
}

output "vision_service_account_email" {
  description = "Email of the Vision API service account"
  value       = google_service_account.vision_api_sa.email
}

output "vision_service_account_key" {
  description = "Base64-encoded private key for Vision API service account (sensitive)"
  value       = google_service_account_key.vision_api_key.private_key
  sensitive   = true
}

output "vision_credentials_path" {
  description = "Path to the Vision API credentials file (if stored locally)"
  value       = var.store_credentials_locally ? local_file.vision_api_credentials[0].filename : "Use Secret Manager in production"
}
