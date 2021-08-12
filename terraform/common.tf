# vim: ts=2 sw=2 et

# INPUTS

variable "client_id" {
  type = string
  description = "The UUID of the endpoint."
}

variable "project_id" {
  type = string
  description = "The ID of the Google Cloud project that will hold this image."
}

variable "region" {
  type = string
  description = "The region to use, within Google Cloud."
}

variable "cloudfunctions_region" {
  type = string
  description = "The region to use for Cloud Functions."
}

variable "zone" {
  type = string
  description = "For zonal resources, the zone to use, within the region."
}

variable "ssh_client_subnets" {
  type = list(string)
  description = "The list of subnets that are allowed to connect to select VMs via SSH.  Set to 127.0.0.1/32 to disable."
  default = ["127.0.0.1/32"]
}

variable "enable_gcs" {
  type = bool
  description = "Set to true to enable GCS deployment."
  default = false
}

# TERRAFORM CONFIG

terraform {
  required_version = "~> 0.14.9"

  required_providers {
    google = {
      version = "~> 3.78.0"
      source = "hashicorp/google"
    }
  }

  backend "gcs" {
  }
}

# PROVIDER CONFIG

provider "google" {
  project = var.project_id
  region = var.region
  zone = var.zone
}

# SERVICE ACCOUNT LOCKDOWN

# By default, Google's default service accounts have the following roles:
# * Compute Engine: Editor
# (There are other default service accounts, but this project should only have
# the ones listed above.)
# Some of those service accounts are too powerful.  So, we de-privilege all of
# them, and then explicitly grant privileges where needed.

# The following default service accounts are not touched by this code:
# * Cloud Build
# * Google APIs Service Agent

resource "google_project_default_service_accounts" "globus" {
  project = var.project_id
  action = "DEPRIVILEGE"
}

# COMPUTE ENGINE COMMON CONFIGURATION

# This sets Compute Engine default metadata, including project-wide SSH keys.
# Project-wide SSH keys should not be used.  Either set the SSH keys in
# instance metadata, or use OS Login.
# Right now, all we do is switch to Zonal DNS.
# (See https://cloud.google.com/compute/docs/internal-dns#migrating-to-zonal)
resource "google_compute_project_metadata" "zonal_dns" {
  metadata = {
    VmDnsSetting = "ZonalOnly"
  }
}

# MODULES

module "packer" {
  source = "./packer"

  region = var.region
  cloudfunctions_region = var.cloudfunctions_region
  zone = var.zone
  firewall_subnets = var.ssh_client_subnets
}

module "gcs" {
  source = "./gcs"

  count = var.enable_gcs == true ? 1 : 0

  client_id = var.client_id
  region = var.region
}

# OUTPUTS

output "packer_service_account_id" {
  value = module.packer.service_account_id
}

output "packer_project_id" {
  value = module.packer.project_id
}

output "packer_zone" {
  value = module.packer.zone
}

output "packer_subnet_id" {
  value = module.packer.subnet_id
}

output "packer_image_pubsub_topic" {
  value = module.packer.image_pubsub_topic
}

output "packer_slack_pubsub_topic" {
  value = module.packer.slack_pubsub_topic
}
