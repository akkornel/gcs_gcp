# vim: ts=2 sw=2 et
# -*- coding: utf-8 -*-

# © 2021 The Board of Trustees of the Leland Stanford Junior University.

# The content is based on the Cloud Builders Community Packer builder,
# https://github.com/GoogleCloudPlatform/cloud-builders-community/blob/master/packer/Dockerfile,
# commit ID 781ef078f408f309ab7dbc8a7eeacb3cd5af524e,
# which originally had the following copyright & license:
# Copyright 2017 Google, Inc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Alpine Linux is used for verifying & unpacking the Packer binary.
FROM alpine:3.11 AS build

ARG PACKER_VERSION
ARG PACKER_VERSION_SHA256SUM

COPY packer_${PACKER_VERSION}_linux_amd64.zip .
RUN echo "${PACKER_VERSION_SHA256SUM}  packer_${PACKER_VERSION}_linux_amd64.zip" > checksum && sha256sum -c checksum

RUN /usr/bin/unzip packer_${PACKER_VERSION}_linux_amd64.zip

# Use the Google Cloud SDK Docker image as the base.
FROM gcr.io/google.com/cloudsdktool/cloud-sdk:latest
RUN apt-get -y update && apt-get -y install ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build packer /usr/bin/packer
ENTRYPOINT ["/usr/bin/packer"]
