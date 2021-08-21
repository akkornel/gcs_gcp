# vim: ts=2 sw=2 et

# IAM (including SERVICE ACCOUNTS)

# GCS management nodes have their own service account, seprate from DTNs.
resource "google_service_account" "gcs_dtn_vm" {
    depends_on = [google_project_service.iam]
    account_id = "gcs-dtn-vm"
    display_name = "GCS DTN VM service account"
    description = "Used for management of GCS secrets and configuration"
}

# Allow the different roles needed for the instance scopes listed in the
# template (which are a subset of the "default" scopes).  These need to be
# granted also to the service account for GCS management nodes, so the
# configuration is in a sub-module.
module "gcs_dtn_vm_sa_common_config" {
    source = "./sa_common"
    account_email = google_service_account.gcs_dtn_vm.email
    deployment_secret_id = google_secret_manager_secret.deployment.secret_id
    slack_pubsub_topic = var.slack_pubsub_topic
}

# NETWORK

# This is the subnet for DTNs.  It is needed because management nodes go
# through a Cloud NAT, and the Cloud NAT selects traffic based on subnet.
resource "google_compute_subnetwork" "gcs_dtn" {
  name = "gcs-dtn"
  description = "The subnet for DTNs"
  ip_cidr_range = "10.210.2.0/24"
  region = var.region
  network = google_compute_network.gcs.id
}

# FIREWALL

# Allow SSH from management nodes
resource "google_compute_firewall" "gcs-dtn-ssh-management" {
  name = "gcs-dtn-ssh-management"
  description = "Allow inbound SSH from management nodes"
  network = google_compute_network.gcs.id

  direction = "INGRESS"
  source_tags = ["gcs-management"]
  target_tags = ["gcs-dtn"]
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# Allow SSH traffic in through the Google Identity-Aware Proxy
resource "google_compute_firewall" "gcs-dtn-ssh-iap" {
  name = "gcs-dtn-ssh-iap"
  description = "Allow SSH inbound via the Identity-Aware Proxy"
  network = google_compute_network.gcs.id

  direction = "INGRESS"
  source_ranges = data.google_netblock_ip_ranges.iap_forwarders.cidr_blocks
  target_tags = ["gcs-dtn"]
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# Allow web (TLS) traffic in to the DTNs.
resource "google_compute_firewall" "gcs-dtn-web" {
  name = "gcs-dtn-web"
  description = "Allow inbound to Globus DTN web"
  network = google_compute_network.gcs.id

  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["gcs-dtn"]
  allow {
    protocol = "tcp"
    ports = ["443"]
  }
}

# Allow GridFTP data traffic in to the DTNs.
resource "google_compute_firewall" "gcs-dtn-data" {
  name = "gcs-dtn-data"
  description = "Allow inbound to GridFTP data ports"
  network = google_compute_network.gcs.id

  direction = "INGRESS"
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["gcs-dtn"]
  allow {
    protocol = "tcp"
    ports = ["50000-51000"]
  }
  allow {
    protocol = "udp"
    ports = ["50000-51000"]
  }
}

# COMPUTE

resource "google_compute_instance_template" "dtn" {
    depends_on = [google_project_service.computeengine]
    name = "gcs-dtn"
    description = "Define the template for DTNs"

    # TODO: Select a more-appropriate machine type
    machine_type = "n2d-standard-4"
    region = var.region

    # Identity & Scopes
    # The scopes we request are based on the "default" set of scopes.
    # See https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes#--scopes
    # We also add a scope for Pub/Sub access.
    # Then we ruin it all by adding the wildcard scope for Secrets Manager.
    service_account {
        email = google_service_account.gcs_dtn_vm.email
        scopes = [
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/logging.write",
            "https://www.googleapis.com/auth/monitoring.write",
            "https://www.googleapis.com/auth/pubsub",
            "https://www.googleapis.com/auth/service.management.readonly",
            "https://www.googleapis.com/auth/servicecontrol",
            "https://www.googleapis.com/auth/trace.append"
        ]
    }

    # Management
    instance_description = "DTN"
    metadata = {
        enable-oslogin = "TRUE"
        type = "dtn"
        globus_client_id = var.client_id
        slack_topic_id = var.slack_pubsub_topic
    }
    scheduling {
        preemptible = false
        automatic_restart = true
        on_host_maintenance = "TERMINATE"
    }

    # Security
    shielded_instance_config {
        enable_vtpm = true
        enable_secure_boot = true
        enable_integrity_monitoring = true
    }
    confidential_instance_config {
        enable_confidential_compute = false
    }

    # Disks
    disk {
        source_image = data.google_compute_image.gcs.self_link
        auto_delete = true
    }

    # Networking
    # TODO: Investigate nic_type = GVNIC
    network_interface {
        nic_type = "VIRTIO_NET"
        subnetwork = google_compute_subnetwork.gcs_dtn.name
        access_config {
            network_tier = "STANDARD"
        }
    }
    tags = ["gcs-dtn"]
    can_ip_forward = false
}
