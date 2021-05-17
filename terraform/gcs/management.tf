# vim: ts=2 sw=2 et

# IAM (including SERVICE ACCOUNTS)

# GCS management nodes have their own service account, seprate from DTNs.
resource "google_service_account" "gcs_management_vm" {
    depends_on = [google_project_service.iam]
    account_id = "gcs-management-vm"
    display_name = "GCS Management VM service account"
    description = "Used for management of GCS secrets and configuration"
}

# Allow the different roles needed for the instance scopes listed in the
# template (which are a subset of the "default" scopes).  These need to be
# granted also to the service account for GCS DTNs, so the configuration is in
# a sub-module.
module "gcs_management_vm_sa_common_config" {
    source = "./sa_common"
    account_email = google_service_account.gcs_management_vm.email
}

# Give management nodes read-only access to everything in Google Compute.
resource "google_project_iam_member" "gcs_management_vm_compute_viewer" {
  project = data.google_project.project.project_id
  role = "roles/compute.viewer"
  member = "serviceAccount:${google_service_account.gcs_management_vm.email}"
}

resource "google_project_iam_member" "gcs_management_vm_oslogin_dtn" {
  project = data.google_project.project.project_id
  role = "roles/compute.osAdminLogin"
  member = "serviceAccount:${google_service_account.gcs_management_vm.email}"
  condition {
    title = "Management login to DTNs."
    description = "The management service account may log in to DTN nodes."
    expression = <<EOT
resource.name.startsWith("projects/${data.google_project.project.project_id}/zones/*/instances/gcs-dtn")
EOT
  }
}

# NETWORK

# Create a subnet for management nodes.
# This is needed because the Cloud NAT selects traffic by subnet.
resource "google_compute_subnetwork" "gcs_management" {
  name = "gcs-management"
  description = "The subnet for DTNs and management nodes"
  ip_cidr_range = "10.210.0.0/24"
  region = var.region
  network = google_compute_network.gcs.id
}

# Create a (non-BGP) router, which will host the Cloud NAT.
resource "google_compute_router" "gcs_management" {
  name = "gcs-management"
  region = var.region
  network = google_compute_network.gcs.id
}

# Attach a Cloud NAT to the router.
# The Cloud NAT is configured to only NAT traffic on the management subnet.
# The router works with the default internet gateway to route traffic
# appropriately.
resource "google_compute_router_nat" "gcs_management" {
  name = "gcs-management"
  region = var.region
  router = google_compute_router.gcs_management.name

  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
  subnetwork {
    name = google_compute_subnetwork.gcs_management.self_link
    source_ip_ranges_to_nat = ["PRIMARY_IP_RANGE"]
  }

  udp_idle_timeout_sec = 600
  tcp_established_idle_timeout_sec = 600

  log_config {
    enable = true
    filter = "ALL"
  }
}

# FIREWALL

# Allow SSH traffic in through the Google Identity-Aware Proxy
resource "google_compute_firewall" "gcs-management-ssh-iap" {
  name = "gcs-management-ssh-iap"
  description = "Allow SSH inbound via the Identity-Aware Proxy"
  network = google_compute_network.gcs.id

  direction = "INGRESS"
  source_ranges = data.google_netblock_ip_ranges.iap_forwarders.cidr_blocks
  target_tags = ["gcs-management"]
  allow {
    protocol = "tcp"
    ports = ["22"]
  }
}

# COMPUTE

resource "google_compute_instance_template" "management" {
    depends_on = [google_project_service.computeengine]
    name = "gcs-management"
    description = "Define the template for management nodes"

    machine_type = "e2-micro"
    region = var.region

    # Identity & Scopes
    # The scopes we request are based on the "default" set of scopes.
    # See https://cloud.google.com/sdk/gcloud/reference/alpha/compute/instances/set-scopes#--scopes
    service_account {
        email = google_service_account.gcs_management_vm.email
        scopes = [
            "https://www.googleapis.com/auth/logging.write",
            "https://www.googleapis.com/auth/monitoring.write",
            "https://www.googleapis.com/auth/service.management.readonly",
            "https://www.googleapis.com/auth/servicecontrol",
            "https://www.googleapis.com/auth/trace.append"
        ]
    }

    # Management
    instance_description = "Management node"
    metadata = {
        enable-oslogin = "TRUE"
        type = "management"
        globus_client_id = var.client_id
    }
    scheduling {
        preemptible = false
        automatic_restart = true
        on_host_maintenance = "MIGRATE"
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
        subnetwork = google_compute_subnetwork.gcs_management.name
        # No public IP — NAT will be used for outgoing traffic
    }
    tags = ["gcs-management"]
    can_ip_forward = false
}