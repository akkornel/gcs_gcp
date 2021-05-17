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

source "googlecompute" "deb" {
  # Set project and location based in input variables.
  project_id = var.project_id
  zone = var.zone
  subnetwork = var.subnet_id

  # Choose our Debian source image.
  # Impersonation means that we cannot use OS Login.
  source_image = "debian-10-buster-v20210316"
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
  image_name = "globus-{{timestamp}}"
  image_family = "globus"
  image_description = "Globus image built on {{isotime}}"
}

build {
  sources = [
    "sources.googlecompute.deb"
  ]

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

  # Install the Google Cloud monitoring agent.
  # This is an optional component.  It is not required for Globus to work.
  # Enable or disable it as per your policy.
  # The Cloud Monitoring API must be enabled for this to work.
  # Note that installing the Google Cloud monitoring agent will start the
  # collection of additional metrics that might not be stored for free.
  # See https://cloud.google.com/stackdriver/pricing?#metrics-chargeable
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install the add-apt-repository command
      "apt-get -y install software-properties-common",

      # Import the Google Cloud packages repo and signing key.
      "curl --connect-timeout 5 -s -f 'https://packages.cloud.google.com/apt/doc/apt-key.gpg' | apt-key add -",
      "add-apt-repository 'deb https://packages.cloud.google.com/apt google-cloud-monitoring-buster-all main'",
      "apt-get update",

      # Install and enable the Google Cloud monitoring agent
      "apt-get -y install stackdriver-agent",
      "systemctl enable stackdriver-agent.service",

      # Remove software-properties-common
      "apt-get -y remove software-properties-common"
    ]
  }

  # Install GCSv5.4
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
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
    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      # Install packages required for bootstrap.
      "apt-get -y install python3-venv",

      # Execute the bootstrap script.
      "chmod a+x /tmp/code_bootstrap.sh",
      "/tmp/code_bootstrap.sh"
    ]
  }

  # Final cleanup!
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]

    execute_command = "chmod +x {{ .Path }}; sudo -S sh -c '{{ .Vars }} {{ .Path }}'"

    inline = [
      "apt-get -y autoremove"
    ]
  }
}
