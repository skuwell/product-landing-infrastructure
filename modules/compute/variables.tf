# Compute Module - VM Instances

variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
}

variable "zone" {
  description = "GCP Zone"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "instance_name" {
  description = "Name of the VM instance"
  type        = string
}

variable "machine_type" {
  description = "Machine type for the VM"
  type        = string
  default     = "e2-medium"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 30
}

variable "disk_type" {
  description = "Type of boot disk (pd-standard, pd-ssd, pd-balanced)"
  type        = string
  default     = "pd-standard"
}

variable "image_family" {
  description = "Image family for the boot disk"
  type        = string
  default     = "ubuntu-2004-lts"
}

variable "image_project" {
  description = "Project containing the image"
  type        = string
  default     = "ubuntu-os-cloud"
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
}

variable "subnet_name" {
  description = "Name of the subnet"
  type        = string
}

variable "tags" {
  description = "Network tags for the instance"
  type        = list(string)
  default     = ["ssh-enabled", "http-server", "https-server", "app-server"]
}

variable "startup_script" {
  description = "Startup script for the instance"
  type        = string
  default     = ""
}

variable "service_account_email" {
  description = "Service account email for the instance"
  type        = string
  default     = null
}

variable "enable_external_ip" {
  description = "Assign external IP to the instance"
  type        = bool
  default     = true
}

variable "enable_security_hardening" {
  description = "Apply security hardening via startup script (firewall, fail2ban, auto-updates)"
  type        = bool
  default     = true
}
