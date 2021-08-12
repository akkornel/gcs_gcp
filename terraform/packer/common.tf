# vim: ts=2 sw=2 et

# INPUTS

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

# Setting the subnets list to only include localhost effectively disables it.
variable "firewall_subnets" {
  type = list(string)
  description = "The list of subnets that are allowed to connect to the Packer temporary instance."
  default = ["127.0.0.1/32"]
}

# DATA

# The google_project provider allows us to look up our project ID without it
# needing to be provided to us.
data "google_project" "project" {
}

# The google_compute_default_service_account provider allows us to look up
# the ID of the Compute Engine default service account.
data "google_compute_default_service_account" "default" {
}

# NOTE: The google_netblock_ip_ranges provider allows us to look up the list of
# subnets associated with part of Google.  In this case, we are retrieving the
# list of subnets associated with Google Cloud.
# We do this because Cloud Build does not currently have the ability to run
# within a customer-provided subnet.  Since we have no idea which Google Cloud
# IP might be used by Cloud Build, we must allow all of them.
# Once this is fixed, this block, and
# google_compute_firewall.packer-cloudbuild1 &
# google_compute_firewall.packer-cloudbuild2 can be deleted.
data "google_netblock_ip_ranges" "cloud_netblocks" {
  range_type = "cloud-netblocks"
}

# This is the list of subnets used by the Cloud Identity-Aware Proxy.
data "google_netblock_ip_ranges" "iap_forwarders" {
  range_type = "iap-forwarders"
}

# BUCKETS

# Create a bucket to store Cloud Build artifacts, and manual build source.
# NOTE: Cloud Build does not support specifying a region and zone.  So we
# hard-code the bucket to US.
resource "google_storage_bucket" "cloudbuild-data" {
  name = "${data.google_project.project.project_id}_cloudbuild"
  location = "US"

  # Bucket misc. settings
  force_destroy = true
  versioning {
    enabled = false
  }

  # Bucket security
  uniform_bucket_level_access = true

  # Stroage class and lifecycle rules:
  # Start out in Standard class, move to Coldline after a month, delete in 18.
  storage_class = "STANDARD"
  lifecycle_rule {
    condition {
      age = "32"
    }
    action {
      type = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }
  lifecycle_rule {
    condition {
      age = "548"
    }
    action {
      type = "Delete"
    }
  }
}

# OUTPUTS

output "project_id" {
  value = data.google_project.project.project_id
}

output "service_account_id" {
  value = google_service_account.packer.id
}

output "pubsub_topic" {
  value = google_pubsub_topic.image_updated.id
}

output "subnet_id" {
  value = google_compute_subnetwork.packer.id
}

output "zone" {
  value = var.zone
}
