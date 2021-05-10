# vim: ts=2 sw=2 et

# INPUTS

variable "region" {
  type = string
  description = "The region to use, within Google Cloud."
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

# IAM (including SERVICE ACCOUNTS)

# Packer will have its own service account, to keep it separate from the Globus
# VMs.
resource "google_service_account" "packer" {
  account_id = "packer"
  display_name = "Packer service account"
  description = "Used for Packer to build Globus images."
}

# Allow Cloud Build to use the Packer service account.
# NOTE: This is the not right way to do it.  Instead, we should
# programmatically look up the Cloud Build Service Account, instead of
# constructing it from pieces.  But the method for doing that is currently in
# beta.  Once it comes out of beta, we can use something like this...
#resource "google_cloud_service_identity" "cloudbuild" {
#  project = data.google_project.project.project_id
#  service = "cloudbuild.googleapis.com"
#}
# ... and then use "${google_cloud_service_identity.cloudbuild.email}".
resource "google_service_account_iam_member" "cloudbuild-packer-access-user" {
  service_account_id = google_service_account.packer.name
  role = "roles/iam.serviceAccountUser"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Allow Cloud Build to create tokens to use the Packer service account.
resource "google_service_account_iam_member" "cloudbuild-packer-access-token" {
  service_account_id = google_service_account.packer.name
  role = "roles/iam.serviceAccountTokenCreator"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Allow Packer to use the default Compute Engine service account.
resource "google_service_account_iam_member" "packer-computeengine-access" {
  service_account_id = data.google_compute_default_service_account.default.name
  role = "roles/iam.serviceAccountUser"
  member = "serviceAccount:${google_service_account.packer.email}"
}


# Give Packer read-only access to everything in Google Compute.
resource "google_project_iam_member" "packer-compute-viewer" {
  project = data.google_project.project.project_id
  role = "roles/compute.viewer"
  member = "serviceAccount:${google_service_account.packer.email}"
}

# What follows are the policies granting fine-grained write access to Compute
# Engine.

resource "google_project_iam_member" "packer-compute-instanceadmin" {
  project = data.google_project.project.project_id
  role = "roles/compute.instanceAdmin.v1"
  member = "serviceAccount:${google_service_account.packer.email}"
  condition {
    title = "Packer may manage instances prefixed with packer"
    description = "Packer needs to create & destroy instances in order to build new images."
    expression = <<EOT
resource.name.startsWith("projects/${data.google_project.project.project_id}/zones/${var.zone}/instances/packer")
EOT
  }
}

resource "google_project_iam_member" "packer-compute-instanceadmin-disk" {
  project = data.google_project.project.project_id
  role = "roles/compute.instanceAdmin.v1"
  member = "serviceAccount:${google_service_account.packer.email}"
  condition {
    title = "Packer may manage disks prefixed with packer"
    description = "As part of managing Packer-related instances, Packer needs to be able to managed the attached disks."
    expression = <<EOT
resource.name.startsWith("projects/${data.google_project.project.project_id}/zones/${var.zone}/disks/packer")
EOT
  }
}

resource "google_project_iam_member" "packer-compute-instanceadmin-subnet" {
  project = data.google_project.project.project_id
  role = "roles/compute.instanceAdmin.v1"
  member = "serviceAccount:${google_service_account.packer.email}"
  condition {
    title = "Packer has full access to subnet ${google_compute_subnetwork.packer.name}"
    description = "Packer has its own subnet in which to work."
    expression = <<EOT
resource.name == "${google_compute_subnetwork.packer.id}"
EOT
  }
}

resource "google_project_iam_member" "packer-compute-instanceadmin-image" {
  project = data.google_project.project.project_id
  role = "roles/compute.instanceAdmin.v1"
  member = "serviceAccount:${google_service_account.packer.email}"
  condition {
    title = "Packer may manage images prefixed with packer"
    description = "Packer needs to be able to storage images somewhere in the project."
    expression = <<EOT
resource.name.startsWith("projects/${data.google_project.project.project_id}/global/images/")
EOT
  }
}

# NETWORK

# Packer has its own VPC, to keep it separate from everything else.
# We have a single subnet, and the default route to the outside.
# We also have a firewall rule to allow SSH in, in case Packer is being run
# from outside of Google Cloud.
# Unfortunately, we cannot use the Google Network module because we need to
# pull the subnet's full ID in Service Account policies, and the way the Google
# Network module structures its outputs makes that really hard to access.

resource "google_compute_network" "packer" {
  name = "packer"
  description = "The network for Packer"
  auto_create_subnetworks = false
  mtu = 1500
}

resource "google_compute_subnetwork" "packer" {
  name = "packer"
  description = "The subnet for Packer"
  ip_cidr_range = "10.210.1.0/24"
  region = var.region
  network = google_compute_network.packer.id
}

resource "google_compute_firewall" "packer-external" {
  name = "packer-ssh"
  description = "Allow external SSH inbound to Packer instances"
  network = google_compute_network.packer.id

  direction = "INGRESS"
  source_ranges = var.firewall_subnets
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

resource "google_compute_firewall" "packer-external-iap" {
  name = "packer-ssh-iap"
  description = "Allow SSH inbound via the Identity-Aware Proxy"
  network = google_compute_network.packer.id

  direction = "INGRESS"
  source_ranges = data.google_netblock_ip_ranges.iap_forwarders.cidr_blocks
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# Make two firewall rules, allowing traffic from all Google Cloud IPs in to the
# Packer subnet.  To understand why this is needed, read the comments for
# data.google_netblock_ip_ranges.cloud_netblocks.
resource "google_compute_firewall" "packer-cloudbuild1" {
  name = "packer-ssh-cloudbuild1"
  description = "Allow Cloud Build SSH inbound to Packer instances"
  network = google_compute_network.packer.id

  direction = "INGRESS"
  source_ranges = slice(data.google_netblock_ip_ranges.cloud_netblocks.cidr_blocks_ipv4, 0, 256)
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# As of 2021-05-02, the length of
# data.google_netblock_ip_ranges.cloud_netblocks.cidr_blocks_ipv4 is ~410 list
# items.  The maximum number of subnets in a firewall rule is 256.
# So, the rule is split into two parts.
resource "google_compute_firewall" "packer-cloudbuild2" {
  name = "packer-ssh-cloudbuild2"
  description = "Allow Cloud Build SSH inbound to Packer instances"
  network = google_compute_network.packer.id

  direction = "INGRESS"
  source_ranges = slice(data.google_netblock_ip_ranges.cloud_netblocks.cidr_blocks_ipv4, 256, length(data.google_netblock_ip_ranges.cloud_netblocks.cidr_blocks_ipv4))
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# OUTPUTS

output "project_id" {
  value = data.google_project.project.project_id
}

output "service_account_id" {
  value = google_service_account.packer.id
}

output "subnet_id" {
  value = google_compute_subnetwork.packer.id
}

output "zone" {
  value = var.zone
}
