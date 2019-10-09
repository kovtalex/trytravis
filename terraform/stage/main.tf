provider "google" {
  version = "~>2.15"
  project = var.project
  region  = var.region
}
module "app" {
  source           = "../modules/app"
  name             = "reddit-app"
  machine_type     = "g1-small"
  zone             = var.zone
  tags             = ["reddit-app"]
  public_key_path  = var.public_key_path
  private_key_path = var.private_key_path
  app_disk_image   = var.app_disk_image
  db_internal_ip   = "${module.db.db_internal_ip}"
}
module "db" {
  source           = "../modules/db"
  name             = "reddit-db"
  machine_type     = "g1-small"
  zone             = var.zone
  tags             = ["reddit-db"]
  public_key_path  = var.public_key_path
  private_key_path = var.private_key_path
  db_disk_image    = var.db_disk_image
}
module "vpc" {
  source        = "../modules/vpc"
  source_ranges = ["0.0.0.0/0"]
}

