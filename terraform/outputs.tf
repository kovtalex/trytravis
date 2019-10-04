output "app_external_ip" {
  value = google_compute_instance.default[*].network_interface[0].access_config[0].nat_ip
}
output "lb_app_ip" {
  value = google_compute_global_forwarding_rule.default.ip_address
}
