output "instance_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.vm.name
}

output "instance_id" {
  description = "ID of the VM instance"
  value       = google_compute_instance.vm.id
}

output "instance_self_link" {
  description = "Self link of the VM instance"
  value       = google_compute_instance.vm.self_link
}

output "internal_ip" {
  description = "Internal IP address of the VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address of the VM"
  value       = var.enable_external_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : null
}

output "static_ip" {
  description = "Static IP address"
  value       = var.enable_external_ip ? google_compute_address.static_ip[0].address : null
}

output "zone" {
  description = "Zone of the VM instance"
  value       = google_compute_instance.vm.zone
}
