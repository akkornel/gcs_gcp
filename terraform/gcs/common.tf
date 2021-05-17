# vim: ts=2 sw=2 et

# DATA

# The google_project provider allows us to look up our project ID without it
# needing to be provided to us.
data "google_project" "project" {
}

# SERVICES

# Google IAM
resource "google_project_service" "iam" {
  project = data.google_project.project.project_id
  service = "iamcredentials.googleapis.com"
}

# Google Compute Engine
resource "google_project_service" "computeengine" {
  project = data.google_project.project.project_id
  service = "compute.googleapis.com"
}

# Enable Identity-Aware Proxy, used to TCP forwarding in to Compute Engine VMs.
# This does not block resource creation, as it only comes into play when
# connecting to VMs.
resource "google_project_service" "iap" {
  project = data.google_project.project.project_id
  service = "iap.googleapis.com"
}

# NETWORK

# All of the GCS VMs—management and DTN—live in the same VPC & subnet.
# There is a default route to the outside.
# We have a number of firewall rules in place, allowing specific traffic in to
# specific types of VMs.

resource "google_compute_network" "gcs" {
  name = "gcs"
  description = "The network for DTNs and management nodes"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
  mtu = 1500
}
