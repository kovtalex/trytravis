resource "google_compute_instance" "db" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = var.tags
  metadata = {
    ssh-keys = "appuser:${file(var.public_key_path)}"
  }
  boot_disk {
    initialize_params {
      image = var.db_disk_image
    }
  }
  network_interface {
    network = "default"
    access_config {}
  }

#  connection {
#    type  = "ssh"
#    host  = self.network_interface[0].access_config[0].nat_ip
#    user  = "appuser"
#    agent = false
#    private_key = file(var.private_key_path)
#  }

#  provisioner "remote-exec" {
#    inline = [
#      "sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/g' /etc/mongod.conf && sudo service mongod restart"
#    ]
#  }
}

resource "google_compute_firewall" "firewall_mongo" {
  name = "allow-mongo-default"
  network = "default"
  allow {
    protocol = "tcp"
    ports = ["27017"]
  }
  target_tags = ["reddit-db"]
  source_tags = ["reddit-app"]
}

