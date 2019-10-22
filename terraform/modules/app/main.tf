resource "google_compute_instance" "app" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags
  metadata = {
    ssh-keys = "appuser:${file(var.public_key_path)}"
  }
  boot_disk {
    initialize_params {
      image = var.app_disk_image
    }
  }
  network_interface {
    network = "default"
    access_config {
       nat_ip = google_compute_address.app_ip.address
    }
  }

#  connection {
#    type  = "ssh"
#    host  = self.network_interface[0].access_config[0].nat_ip
#    user  = "appuser"
#    agent = false
#    private_key = file(var.private_key_path)
#  }

#  provisioner "file" {
#    source      = "../modules/app/files/puma.service"
#    destination = "/tmp/puma.service"
#  }

#  provisioner "remote-exec" {
#    inline = [
#      "echo export DATABASE_URL=\"${var.db_internal_ip}\" >> ~/.profile"
#    ]
#  }	

#  provisioner "remote-exec" {
#    script = "../modules/app/files/deploy.sh"
#  }
#depends_on = [var.db_internal_ip]
}

resource "google_compute_address" "app_ip" {
  name = "reddit-app-ip"
}

resource "google_compute_firewall" "firewall_puma" {
  name = "allow-puma-default"
  network = "default"
  allow {
    protocol = "tcp"
    ports    = ["9292"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["reddit-app"]
}
