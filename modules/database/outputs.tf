output "instance_name" {
  description = "Name of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.name
}

output "instance_connection_name" {
  description = "Connection name for Cloud SQL Proxy"
  value       = google_sql_database_instance.postgres.connection_name
}

output "instance_ip_address" {
  description = "IP address of the Cloud SQL instance"
  value       = google_sql_database_instance.postgres.ip_address[0].ip_address
}

output "database_name" {
  description = "Name of the database"
  value       = google_sql_database.database.name
}

output "database_user" {
  description = "Database username"
  value       = google_sql_user.user.name
}

output "database_password_secret" {
  description = "Secret Manager secret name for database password"
  value       = google_secret_manager_secret.db_password.secret_id
}

output "connection_string" {
  description = "PostgreSQL connection string (password from Secret Manager)"
  value       = "postgresql://${google_sql_user.user.name}:PASSWORD_FROM_SECRET_MANAGER@${google_sql_database_instance.postgres.ip_address[0].ip_address}:5432/${google_sql_database.database.name}"
  sensitive   = false
}
