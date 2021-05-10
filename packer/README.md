[//]: # (vim: filetype=markdown ts=4 sw=4 et)
[//]: # (-*- coding: utf-8 -*-)
[//]: # (Comment formatting by https://stackoverflow.com/a/20885980)

# Cloud Build Packer

This Cloud Build job builds a Google Compute Engine image containing Globus
Connect Server.  The intention is for the image to be used to run Globus
Connect Server endpoints with Google Cloud Storage or Google Drive connectors.

In addition to installing Globus Connect Server, this Cloud Build job does some
additional stuff:

* Do an `apt-get update`, to install any updates released since the base image
  was created.

* Install a simple static HTML file to serve on port 80 (even though nobody
  should be accessing port 80).

* Install the Google Cloud monitoring agent, so that metrics like memory usage
  may be recorded & displayed in the Monitoring tab for VMs in Compute Engine.

  Note that this agent only works if the Stackdriver Monitoring API is enabled.

Additional functionality will likely be added in the future.

# Requirements

## Cloud Build

This Cloud Build job's container image needs to be built by the
`packer_builder` Cloud Build job, which should be defined elsewhere within this
repository.

This job assumes that the `packer_builder` job is in the project's Google
Compute Registry, and is named `packer`.

## APIs

To use this, you need the Google Cloud Storage, IAM Credentials, and Cloud
Build APIs.  You can enable all of the required APIs with these commands:

    gcloud services enable storage-component.googleapis.com
    gcloud services enable storage-api.googleapis.com
    gcloud services enable cloudresourcemanager.googleapis.com
    gcloud services enable iamcredentials.googleapis.com
    gcloud services enable cloudbuild.googleapis.com

Before you can enable all of the above APIs, you will need to set up billing on
your project.  Each API may take a few minutes to enable.

## Service Account

A Service Account is required for Packer to run.  In operation, Packer is
started with different permissions (for example, a regular user's credentials,
or the Cloud Build Default Service Account), and then uses
[impersonation](https://cloud.google.com/iam/docs/impersonating-service-accounts)
to act as the Packer Service Account.

The benefit of this method is, you only need to set fine-grained permissions on
the Packer Service Account, instead of on all of the accounts that might
possibly run Packer.

The downside of using impersonation is that
[OS Login](https://cloud.google.com/compute/docs/oslogin) may not be used.  The
API used to upload a key for OS Login takes the 

## Permissions

The Cloud Build Default Service Account needs two roles on the Packer
Service Account:

* `roles/iam.serviceAccountUser`

* `roles/iam.serviceAccountTokenCreator`

The latter permission is needed due to how Packer does the impersonation.

The Packer Service Account needs a number of fine-grained permissions,
expressed as roles with permissions:

* `roles/iam.serviceAccountUser` on the Compute Engine Default Service Account.
  This is so that temporary instances may be launched with that service
  account.

* `roles/compute.viewer`.  This allows read-only access to Compute Engine
  information needed to launch a new VM.  This may be able to be locked down
  more.

* `roles/compute.instanceAdmin.v1`, full access only on instances in a specific
  zone where the instance name starts with "packer".  For this security to
  work, other instances (for example, production instances) must use names that
  do _not_ start with "packer".

* `roles/compute.instanceAdmin.v1`, full access only on disks in a specific
  zone where the disk name starts with "packer".

* `roles/compute.instanceAdmin.v1`, full access only on the Packer subnet.

* `roles/compute.instanceAdmin.v1`, full access to all images.  The intention
  is that Globus Connect Personal images—maintained by this builder—are the
  only images in the project.

# Parameters

To use Packer, you need to set these parameters:

* `_GCR_REGION` is the region of Google Container Registry where the Packer
  image may be found.  You can specify 'us', 'eu', or 'asia'.  It defaults to
  'us'.

* `_PACKER_TAG` is the container image tag to use.  This can either be a
  version number, or "latest".  The default is "latest".

* `_SERVICE_ACCOUNT_EMAIL` is the email address of the Packer Service Account.

* `_PACKER_FILE` is the name of the file, located in the same directory as this
  file, which Packer will use for build instructions.  It defaults to
  "globus.pkr.hcl".

* `_PACKER_DIR` is the path where the Packer files are located.  It defaults to
  ".", the current directory.  If you are running Cloud Build via a trigger,
  and the Packer files are in a sub-directory of the repository, you will need
  to change this to be the path of the sub-directory.

* `_ZONE` is the name of the Compute Engine zone where Packer will temporarily
  create Compute Engine disks and VM instances.  This needs to match the zone
  specified in the fine-grained permissions for the Packer Service Account.

* `_SUBNET` is the name of the VPC Subnet where the temporary Compute Engine VM
  instances will be created.  This needs to be in the region where you zone
  resides.

  Also, this subnet must have a firewall rule that allows SSH connections in
  from Cloud Build.  Unfortunately, it is not possible to put Cloud Build into
  a specific subnet, and Google does not specify a set list of public IPs for
  Cloud Build; until that happens, the firewall rule will need to allow SSH
  from all Google Cloud IP addresses.

# Building

You can build this using a few different ways:

* **Triggers**: This is the preferred method for automation.  Set up a trigger
  that activates whenever something of interest happens, such as a push to a
  branch.

  With this method, you can override default parameters in the trigger
  configuration.  There are also some paraneters that have no default, and so
  you will need to provide a substitution.

  One parameter you will almost always need to override is the `_PACKER_DIR`
  variable.  If the trigger is pulling from a Git repository, that Git repo
  will likely have these files in a sub-directory.  You will need to set
  `_PACKER_DIR` to that sub-directory.

* **Manually**: In a terminal, navigate to this directory and run `gcloud
  builds submit .`.

  With this method, you can override parameters on the command line, like so:
  `gcloud builds submit
  --substitutions=_PACKER_TAG=1.7.0,_GCR_REGION=asia .`.

Note that in both cases, you will need to provide substitutions for
`_SERVICE_ACCOUNT_EMAIL`, `_ZONE`, and `_SUBNET`.  If you fail to do so, manual
builds will not launch, and triggered builds will fail.

# Outputs

This build does not create any images or artifacts as Cloud Build knows them.
Instead, this build will create a Compute Engine image in the "globus" family.
The name of the image will be "globus-" followed by a timestamp.

Note that this build does not do anything to old images.  You will need to
implement some way of deprecating, obsoleting, and deleting old images.
