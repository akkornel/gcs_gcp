[//]: # (vim: filetype=markdown ts=4 sw=4 et)
[//]: # (-*- coding: utf-8 -*-)
[//]: # (Comment formatting by https://stackoverflow.com/a/20885980)

# Cloud Build Packer Builder

This Cloud Build job builds a container image containing
[Packer](http://packer.io), which is a tool for building custom cloud images,
using a basic cloud image as a base.

The intended use of this Packer image is to build Google Compute Engine VM
images containing Globus Connect Server.  But it could be used for other
things.

# Requirements

## APIs

To use this, you need the Google Cloud Storage, Cloud Build, and Container
Registry APIs.  You can enable all of the required APIs with these commands:

    gcloud services enable storage-component.googleapis.com
    gcloud services enable storage-api.googleapis.com
    gcloud services enable cloudresourcemanager.googleapis.com
    gcloud services enable cloudbuild.googleapis.com
    gcloud services enable containerregistry.googleapis.com

Before you can enable all of the above APIs, you will need to set up billing on
your project.  Each API may take a few minutes to enable.

## Permissions

No special permissions are required for this build.  The Cloud Build Service
Account's default permissions give it everything needed to build and push the
image.

# Parameters

To build the Packer builder, you need to set three parameters:

* `_PACKER_VERSION` is the version number of Packer to download.

* `_PACKER_VERSION_SHA256SUM` is the SHA-256 checksum of the Linux amd64 build
  of the specified Packer version (the .zip file, not the actual binary).

* `_GCR_REGION` is the region of Google Container Registry to save the built
  container.  You can specify 'us', 'eu', or 'asia'.

At this time, the Cloud Build configuration defaults to using Packer version
1.7.4, and uploading to the 'us' GCR region.

# Building

You can build this using a few different ways:

* **Triggers**: This is the preferred method for automation.  Set up a trigger
  that activates whenever something of interest happens, such as a push to a
  branch.

  With this method, you can override parameters in the trigger configuration.

* **Manually**: In a terminal, navigate to this directory and run `gcloud
  builds submit .`.

  With this method, you can override parameters on the command line, like so:
  `gcloud builds submit
  --substitutions=_PACKER_VERSION=1.7.3,_PACKER_VERSION_SHA256SUM=abcdef .`.

# Outputs

This build will create a container image in Google Container Registry, named
`packer`, and tagged with "latest" and the specific version number.
