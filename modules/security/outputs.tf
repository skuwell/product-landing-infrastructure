output "app_service_account_email" {
  description = "Email of the application service account"
  value       = google_service_account.app_sa.email
}

output "terraform_service_account_email" {
  description = "Email of the Terraform service account"
  value       = google_service_account.terraform_sa.email
}

output "app_secret_key_name" {
  description = "Name of the app secret key in Secret Manager"
  value       = google_secret_manager_secret.app_secret_key.secret_id
}
