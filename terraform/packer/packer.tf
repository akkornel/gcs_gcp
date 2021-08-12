# vim: ts=2 sw=2 et

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

# These are permissions on the Cloud Build Default Service Account

# Allow Cloud Build to post messages to the Pub/Sub topic
resource "google_pubsub_topic_iam_member" "cloudbuild-pubsub-post" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.image_updated.name
  role = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# Allow Cloud Build to read source files for manual builds
resource "google_project_iam_member" "cloudbuild-storage-source-read" {
  project = data.google_project.project.project_id
  role = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  condition {
    title = "Cloud Build may read from source storage"
    description = "When manual builds are submitted, this is where the source files are stored."
    expression = <<EOT
resource.name.startsWith("projects/_/buckets/uit-uit-et-globusmigrate-dev_cloudbuild/objects/source/")
EOT
  }
}

# Allow Cloud Build to write build artifacts
resource "google_project_iam_member" "cloudbuild-storage-artifacts-write" {
  project = data.google_project.project.project_id
  role = "roles/storage.objectCreator"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  condition {
    title = "Cloud Build may write to artifacts storage"
    description = "Cloud build must be able to upload artifacts from builds."
    expression = <<EOT
resource.name.startsWith("projects/_/buckets/uit-uit-et-globusmigrate-dev_cloudbuild/objects/artifacts/")
EOT
  }
}

# These are permissions on the Packer Service Account

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

# What follows are fine-grained permissions for the Cloud Build bucket.

# Give Cloud Build write access to upload artifacts
resource "google_project_iam_member" "cloudbuild-storage-write-artifacts" {
  project = data.google_project.project.project_id
  role = "roles/storage.objectCreator"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  condition {
    title = "Cloud Build may write to artifacts storage"
    description = "Cloud build must be able to upload artifacts from builds."
    expression = <<EOT
resource.name.startsWith("projects/_/buckets/${google_storage_bucket.cloudbuild-data.name}/objects/artifacts/")
EOT
  }
}

# Give Cloud Build read access to source uplaods from manual builds.
resource "google_project_iam_member" "cloudbuild-storage-read-source" {
  project = data.google_project.project.project_id
  role = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
  condition {
    title = "Cloud Build may read from source storage"
    description = "When manual builds are submitted, this is where the source files are stored."
    expression = <<EOT
resource.name.startsWith("projects/_/buckets/${google_storage_bucket.cloudbuild-data.name}/objects/source/")
EOT
  }
}

# PUB/SUB

# Pub/Sub is used to send notices when a new image has been built.
# Each message is a JSON object containing a single key, `image_name`.  The
# value is a string, containing the name of the just-built image.

resource "google_pubsub_schema" "image_updated" {
  name = "image-updated"
  type = "AVRO"
  definition = <<-EOT
  {
   "type" : "record",
   "name" : "Avro",
   "fields" : [
     {
       "name" : "image_name",
       "type" : "string"
     }
   ]
  }
  EOT
}

resource "google_pubsub_topic" "image_updated" {
  name = "image-updated"

  schema_settings {
    encoding = "JSON"
    schema = google_pubsub_schema.image_updated.id
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
