# Networking
output "network_name" {
  description = "VPC network name"
  value       = module.networking.network_name
}

output "subnet_name" {
  description = "Subnet name"
  value       = module.networking.subnet_name
}

# Compute
output "vm_name" {
  description = "VM instance name"
  value       = module.compute.instance_name
}

output "vm_external_ip" {
  description = "External IP address of the VM"
  value       = module.compute.external_ip
}

output "vm_ssh_command" {
  description = "SSH command to connect using gcloud"
  value       = "gcloud compute ssh ${module.compute.instance_name} --zone=${var.zone} --project=${var.project_id}"
}

# Database
output "db_instance_name" {
  description = "Cloud SQL instance name"
  value       = module.database.instance_name
}

output "db_connection_name" {
  description = "Cloud SQL connection name (used with Cloud SQL Auth Proxy)"
  value       = module.database.instance_connection_name
}

# Storage
output "uploads_bucket" {
  description = "GCS uploads bucket name"
  value       = module.storage.uploads_bucket_name
}

output "backups_bucket" {
  description = "GCS daily pg_dump backups bucket name"
  value       = module.storage.backups_bucket_name
}

# Security
output "app_service_account" {
  description = "Application service account email"
  value       = module.security.app_service_account_email
}

# Deployment summary
output "deployment_info" {
  description = "Post-deployment reference information"
  value = <<-EOT

    ========================================
    product-landing-app DEPLOYED
    ========================================

    VM:
      Name  : ${module.compute.instance_name}
      IP    : ${module.compute.external_ip}
      SSH   : gcloud compute ssh ${module.compute.instance_name} --zone=${var.zone} --project=${var.project_id}

    Database (Cloud SQL):
      Instance : ${module.database.instance_name}
      Connect  : ${module.database.instance_connection_name}

    Storage:
      Uploads : gs://${module.storage.uploads_bucket_name}
      Backups : gs://${module.storage.backups_bucket_name}

    Service Account:
      ${module.security.app_service_account_email}

    Next steps:
      1. Point your DNS A-record to ${module.compute.external_ip}
      2. Wait ~5 min for startup script to complete (check: sudo journalctl -u google-startup-scripts -f)
      3. Visit https://${var.domain != "" ? var.domain : module.compute.external_ip}

    ========================================
  EOT
}
