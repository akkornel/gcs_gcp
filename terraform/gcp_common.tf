# vim: ts=2 sw=2 et

# INPUTS

variable "project_id" {
  type = string
  description = "The ID of the Google Cloud project that will hold this image."
}

variable "region" {
  type = string
  description = "The region to use, within Google Cloud."
}

variable "zone" {
  type = string
  description = "For zonal resources, the zone to use, within the region."
}

# TERRAFORM CONFIG

terraform {
  required_version = "~> 0.14.9"

  required_providers {
    google = {
      version = "~> 3.65.0"
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
