# VM Instance
resource "google_compute_instance" "vm" {
  name         = "${var.instance_name}-${var.environment}"
  project      = var.project_id
  machine_type = var.machine_type
  zone         = var.zone
  
  tags = var.tags
  
  boot_disk {
    initialize_params {
      image = "projects/${var.image_project}/global/images/family/${var.image_family}"
      size  = var.disk_size_gb
      type  = var.disk_type
    }
  }
  
  network_interface {
    network    = var.network_name
    subnetwork = var.subnet_name
    
    dynamic "access_config" {
      for_each = var.enable_external_ip ? [1] : []
      content {
        // Ephemeral public IP
      }
    }
  }
  
  metadata = {
    enable-oslogin = "TRUE"
  }
  
  metadata_startup_script = var.enable_security_hardening ? templatefile("${path.module}/security-startup.sh", {}) : (
    var.startup_script != "" ? var.startup_script : templatefile("${path.module}/startup-script.sh", {
      environment = var.environment
    })
  )
  
  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }
  
  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = var.environment == "dev" ? false : false  # Can enable for dev
  }
  
  labels = {
    environment = var.environment
    managed_by  = "terraform"
  }
  
  allow_stopping_for_update = true
}

# Static IP (optional)
resource "google_compute_address" "static_ip" {
  count   = var.enable_external_ip ? 1 : 0
  name    = "${var.instance_name}-static-ip-${var.environment}"
  project = var.project_id
  region  = var.region
}
