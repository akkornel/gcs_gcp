# vim: ts=2 sw=2 et

# INPUTS

variable "client_id" {
  type = string
  description = "The UUID of the endpoint."
}

variable "region" {
  type = string
  description = "The region to use, within Google Cloud."
}

variable "slack_pubsub_topic" {
  type = string
  description = "The Pub/Sub Topic to use, when posting to Slack."
}

# DATA

# The google_project provider allows us to look up our project ID without it
# needing to be provided to us.
data "google_project" "project" {
}

# A single image is used for both DTNs and management nodes.  Look it up here.
data "google_compute_image" "gcs" {
  family = "globus"
  project = data.google_project.project.project_id
}

# This is the list of subnets used by the Cloud Identity-Aware Proxy.
data "google_netblock_ip_ranges" "iap_forwarders" {
  range_type = "iap-forwarders"
}

# SERVICES

# Google IAM
resource "google_project_service" "iam" {
  project = data.google_project.project.project_id
  service = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

# Google Compute Engine
resource "google_project_service" "computeengine" {
  project = data.google_project.project.project_id
  service = "compute.googleapis.com"
  disable_on_destroy = false
}

# Enable Identity-Aware Proxy, used to TCP forwarding in to Compute Engine VMs.
# This does not block resource creation, as it only comes into play when
# connecting to VMs.
resource "google_project_service" "iap" {
  project = data.google_project.project.project_id
  service = "iap.googleapis.com"
  disable_on_destroy = false
}

# Enable Secret Manager to store sensitive configuration information.
resource "google_project_service" "secret" {
  project = data.google_project.project.project_id
  service = "secretmanager.googleapis.com"
  disable_on_destroy = false
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
