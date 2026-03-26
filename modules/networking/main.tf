# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.vpc_name}-${var.environment}"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC network for ${var.environment} environment"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.vpc_name}-subnet-${var.environment}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = var.subnet_cidr
  
  private_ip_google_access = true
  
  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router for Cloud NAT
resource "google_compute_router" "router" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${var.vpc_name}-router-${var.environment}"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT
resource "google_compute_router_nat" "nat" {
  count  = var.enable_cloud_nat ? 1 : 0
  name   = "${var.vpc_name}-nat-${var.environment}"
  router = google_compute_router.router[0].name
  region = var.region
  
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
  
  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Firewall Rule - Allow SSH
resource "google_compute_firewall" "allow_ssh" {
  name    = "${var.vpc_name}-allow-ssh-${var.environment}"
  project = var.project_id
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  
  source_ranges = var.allowed_ssh_cidr_ranges
  target_tags   = ["ssh-enabled"]
  
  description = "Allow SSH access from specified CIDR ranges"
}

# Firewall Rule - Allow HTTP/HTTPS
resource "google_compute_firewall" "allow_http_https" {
  name    = "${var.vpc_name}-allow-http-https-${var.environment}"
  project = var.project_id
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }
  
  source_ranges = var.allowed_http_cidr_ranges
  target_tags   = ["http-server", "https-server"]
  
  description = "Allow HTTP/HTTPS access from specified CIDR ranges"
}

# Firewall Rule - Allow Internal Communication
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.vpc_name}-allow-internal-${var.environment}"
  project = var.project_id
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  
  allow {
    protocol = "icmp"
  }
  
  source_ranges = [var.subnet_cidr]
  
  description = "Allow internal communication within the VPC"
}

# Firewall Rule - Allow Application Ports
resource "google_compute_firewall" "allow_app_ports" {
  name    = "${var.vpc_name}-allow-app-${var.environment}"
  project = var.project_id
  network = google_compute_network.vpc.name
  
  allow {
    protocol = "tcp"
    ports    = ["8000", "5000", "5432", "6379"]  # Backend, webhook, PostgreSQL, Redis
  }
  
  source_ranges = var.allowed_http_cidr_ranges
  target_tags   = ["app-server"]
  
  description = "Allow access to application ports"
}

# Firewall Rule - Deny All Other Ingress (implicit, but explicit for clarity)
resource "google_compute_firewall" "deny_all_ingress" {
  name     = "${var.vpc_name}-deny-all-ingress-${var.environment}"
  project  = var.project_id
  network  = google_compute_network.vpc.name
  priority = 65534
  
  deny {
    protocol = "all"
  }
  
  source_ranges = ["0.0.0.0/0"]
  
  description = "Deny all other ingress traffic"
}
