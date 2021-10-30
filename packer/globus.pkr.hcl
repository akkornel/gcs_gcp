# vim: ts=2 sw=2 et

# © 2021 The Board of Trustees of the Leland Stanford Junior University.
# All Rights Reserved (for now!).

variable "project_id" {
  type = string
  description = "The ID of the Google Cloud project that will hold this image."
}

variable "zone" {
  type = string
  description = "The zone to use, within Google Cloud."
}

variable "subnet_id" {
  type = string
  description = "The ID of the subnet to use for builder instances."
}

variable "service_account" {
  type = string
  description = "The Service Account to impersonate in all GCP operations."
}

variable "completion_pubsub_topic" {
  type = string
  description = "The Pub/Sub Topic to notify on completion."
}

variable "slack_pubsub_topic" {
  type = string
  description = "The Pub/Sub Topic to notify with updates."
}

# This is a timestamp.  We define it as a local variable because we want it
# "frozen", so that we can use the same timestamp multiple times.
local "build_timestamp" {
  expression = timestamp()
  sensitive = false
}

# This is the build time, which will be used in image descriptions.
# This variable's definition uses the HCL2 timestamp():
# https://www.packer.io/docs/templates/hcl_templates/functions/datetime/timestamp
local "build_time" {
  expression = formatdate("YYYY-MM-DD'Z'hh:mm", local.build_timestamp)
  sensitive = false
}

# This is the name of the Compute Engine image.
# It's defined here because we'll use it in multiple places, such as the image
# name and the artifact paths in Cloud Storage.
local "image_name" {
  expression = "globus-${formatdate("YYYYMMDDhhmmss", local.build_timestamp)}"
  sensitive = false
}

source "googlecompute" "deb" {
  # Set project and location based in input variables.
  project_id = var.project_id
  zone = var.zone
  subnetwork = var.subnet_id

  # Choose our Debian source image.
  # Impersonation means that we cannot use OS Login.
  source_image_family = "debian-10"
  disk_size = 10
  ssh_username = "packer"
  use_os_login = false

  # User Service Account impersonation.  This simplifies permissions.
  # See the README for requirements.
  impersonate_service_account = var.service_account

  # Use a preemptible VM for building.
  preemptible = true

  # Give our builder instance a useful name.
  instance_name = "packer-{{uuid}}"

  # Attributes to use for the created image.
  image_name = "${local.image_name}"
  image_family = "globus"
  image_description = "Globus image built on ${local.build_time}"
}

build {
  sources = [
    "sources.googlecompute.deb"
  ]

  # Post a Pub/Sub notification to say we are building a new image.
  provisioner "shell-local" {
    inline = [
      "gcloud pubsub topics publish --message '{\"text\": \":clock1: `${local.image_name}` bulld running...\"}' ${var.slack_pubsub_topic}"
    ]
  }

  # Upgrade out-of-date packages
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      "apt-get update",
      "apt-get -y dist-upgrade"
    ]
  }

  # Install the Google Cloud Ops agent.
  # This is an optional component.  It is not required for Globus to work.
  # Enable or disable it as per your policy.
  # The Cloud Monitoring API must be enabled for this to work.
  # Note that installing the Google Cloud monitoring agent will start the
  # collection of additional metrics that might not be stored for free.
  # See https://cloud.google.com/stackdriver/pricing?#metrics-chargeable
  # apt-key environment variable from https://stackoverflow.com/questions/48162574
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install the add-apt-repository command
      "apt-get -y install software-properties-common",

      # Import the Google Cloud Ops Agent packages repo and signing key.
      "curl --connect-timeout 5 -s -f 'https://packages.cloud.google.com/apt/doc/apt-key.gpg' | apt-key add -",
      "add-apt-repository 'deb https://packages.cloud.google.com/apt google-cloud-ops-agent-buster-all main'",
      "apt-get update",

      # Install and enable the Google Cloud Ops agent.
      # (It's enabled automatically during installation)
      "systemctl enable stackdriver-agent.service",

      # Remove software-properties-common
      "apt-get -y remove software-properties-common"
    ]
  }

  # Install GCSv5.4
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install the add-apt-repository command
      "apt-get -y install software-properties-common",

      # Import the Globus key & repo
      "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 44AE7EC2FAF24365",
      "add-apt-repository 'deb https://downloads.globus.org/globus-connect-server/stable/deb buster contrib'",
      "add-apt-repository 'deb https://downloads.globus.org/toolkit/gt6/stable/deb buster contrib'",
      "apt-get update",

      # Install GCSv5.4
      "apt-get -y install globus-connect-server54",

      # Remove software-properties-common
      "apt-get -y remove software-properties-common"
    ]
  }

  # Install and configure auditd.
  # This includes copying audit config files.
  provisioner "file" {
    source = "auditd_rules/"
    destination = "/tmp/"
  }
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install auditd & plugins.
      "apt-get -y install auditd audispd-plugins",

      # Remove the default rules file
      "rm -f /etc/audit/rules.d/audit.rules",

      # Move the uploaded rules into palce"
      "mv /tmp/auditd_rules/* /etc/audit/rules.d/",
      "rmdir /tmp/auditd_rules",

      # Rebuild the combined auditd rules.
      # Change takes effect when the deployed nodes are booted.
      "augengules"
    ]
  }

  # Remove all packages not directly installed.
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      "apt-get -y autoremove"
    ]
  }

  # From this point forward, anything with does an `apt-get remove` is
  # responsible for their own autoremove.

  # Copy a file to replace the default Apache index file.
  provisioner "file" {
    source = "port80_index.html"
    destination = "/tmp/port80_index.html"
  }
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      "mv /tmp/port80_index.html /var/www/html/index.html",
      "chmod 0644 /var/www/html/index.html"
    ]
  }

  # Copy the entire workspace directory (which should be the entire Git repo).
  # Note that the shell provisioner here does not run under sudo.  That is
  # because we are doing a mkdir in /tmp, and we don't want the directory to be
  # owned by root.
  provisioner "shell" {
    inline = [
      "mkdir /tmp/workspace"
    ]
  }
  provisioner "file" {
    # Ending the source path in / is important here.
    source = "../"
    destination = "/tmp/workspace"
  }

  # Copy and run the bootstrap script.
  provisioner "file" {
    source = "code_bootstrap.sh"
    destination = "/tmp/code_bootstrap.sh"
  }
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install packages required for bootstrap.
      "apt-get -y install python3-venv python3-systemd",

      # Execute the bootstrap script.
      "chmod a+x /tmp/code_bootstrap.sh",
      "/tmp/code_bootstrap.sh"
    ]
  }

  # Dump package version information, and copy out of the build system.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      "dpkg-query -W > /tmp/dpkg_pkglist.txt",
      "/opt/gcs_gcp/bin/pip list --pre --format freeze > /tmp/pip_pkglist.txt",
      "chmod a+r /tmp/dpkg_pkglist.txt /tmp/pip_pkglist.txt"
    ]
  }
  provisioner "file" {
    direction = "download"
    source = "/tmp/dpkg_pkglist.txt"
    destination = "/tmp/dpkg_pkglist.txt"
  }
  provisioner "file" {
    direction = "download"
    source = "/tmp/pip_pkglist.txt"
    destination = "/tmp/pip_pkglist.txt"
  }

  # Copy artifacts to Cloud Storage
  post-processor "shell-local" {
    inline = [
      "gsutil cp /tmp/dpkg_pkglist.txt gs://${var.project_id}_cloudbuild/artifacts/build-lists/${local.image_name}/dpkg_pkglist.txt",
      "gsutil cp /tmp/pip_pkglist.txt gs://${var.project_id}_cloudbuild/artifacts/build-lists/${local.image_name}/pip_pkglist.txt"
    ]
  }

  # Post a Pub/Sub notification with the name of the new image.
  post-processor "shell-local" {
    inline = [
      "gcloud pubsub topics publish --message '{\"image_name\": \"${local.image_name}\"}' ${var.completion_pubsub_topic}",
      "gcloud pubsub topics publish --message '{\"text\": \":tada: `${local.image_name}` bulld complete!\"}' ${var.slack_pubsub_topic}"
    ]
  }
}
