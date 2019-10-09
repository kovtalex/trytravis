variable name {
  description = "Db name"
  default = "reddit-db"
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
variable db_disk_image {
  description = "Disk image for reddit db"
  default     = "reddit-db-base"
}
