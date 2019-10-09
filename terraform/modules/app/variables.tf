variable name {
  description = "App name"  
  default = "reddit-app"
}
variable machine_type {
  description = "Machine type"
  default     = "g1-small"
}
variable zone {
  description = "Zone"
  default     = "europe-west1-b"
}
variable tags {
  description = "tags"
}
variable public_key_path {
  description = "Path to the public key used to connect to instance"
}
variable private_key_path {
  description = "Path to the private key used for ssh access"
}
variable app_disk_image {
  description = "Disk image for reddit app"
  default     = "reddit-app-base"
}
variable db_internal_ip {
}
