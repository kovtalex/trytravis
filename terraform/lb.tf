resource "google_compute_instance_group" "default" {
  name = "reddit-group"
  zone = var.zone

  instances = "${google_compute_instance.default.*.self_link}"

  named_port {
    name = "http"
    port = "9292"
  }
}

resource "google_compute_global_address" "default" {
  name = "reddit-ip"
}

resource "google_compute_global_forwarding_rule" "default" {
  name       = "reddit-rule"
  target     = "${google_compute_target_http_proxy.default.self_link}"
  port_range = "80"
}

resource "google_compute_target_http_proxy" "default" {
  name    = "reddit-proxy"
  url_map = "${google_compute_url_map.default.self_link}"
}


resource "google_compute_url_map" "default" {
  name            = "reddit-urlmap"
  default_service = "${google_compute_backend_service.default.self_link}"
}

resource "google_compute_backend_service" "default" {
  name      = "reddit-service"
  port_name = "http"
  protocol  = "HTTP"

  backend {
    group = "${google_compute_instance_group.default.self_link}"
  }

  health_checks = [
    "${google_compute_health_check.default.self_link}",
  ]
}

resource "google_compute_health_check" "default" {
  name               = "reddit-health"
  timeout_sec        = 1
  check_interval_sec = 1

  http_health_check {
    port = "9292"
  }
}

