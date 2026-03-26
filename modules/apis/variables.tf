# Variables for Google Cloud APIs Module

variable "project_id" {
  description = "The GCP project ID"
  type        = string
}

variable "store_credentials_locally" {
  description = "Whether to store service account credentials locally (not recommended for production)"
  type        = bool
  default     = false
}
