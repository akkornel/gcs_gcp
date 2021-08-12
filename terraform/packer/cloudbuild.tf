# vim: ts=2 sw=2 et

# This file contains our Cloud Build triggers and related automation.


# PUB/SUB

resource "google_pubsub_topic" "trigger_build" {
  depends_on = [
    google_project_service.pubsub,
  ]
  name = "trigger_build"
}

# CLOUD SCHEDULER

resource "google_cloud_scheduler_job" "trigger_build" {
  depends_on = [
    google_project_service.scheduler,
  ]
  name = "trigger_build"
  description = "Trigger a Cloud Build job via Pub/Sub"
  schedule = var.build_schedule
  time_zone = var.build_schedule_timezone

  pubsub_target {
    topic_name = google_pubsub_topic.trigger_build.id
    data = base64encode("build!")
  }
}

# IAM

# Give Cloud Scheduler permissions to post to the Pub/Sub Topic
resource "google_pubsub_topic_iam_member" "scheduler_trigger_build_post" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.trigger_build.name
  role = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# Give Cloud Build permissions to subscribe to the Pub/Sub Topic
resource "google_pubsub_topic_iam_member" "cloudbuild_trigger_build_subscribe" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.trigger_build.name
  role = "roles/pubsub.subscriber"
  member = "serviceAccount:${data.google_project.project.number}@cloudbuild.gserviceaccount.com"
}

# CLOUD BUILD TRIGGERS

resource "google_cloudbuild_trigger" "github_main_push" {
  depends_on = [
    google_project_service.cloudbuild
  ]
  name = "github-main-push"
  description = "Build on a push to the main branch"

  github {
    owner = var.github_owner
    name = var.github_name
    push {
      branch = "^main$"
    }
  }
  filename = "packer/cloudbuild.yaml"

  substitutions = {
    _PACKER_DIR = "packer",
    _SLACK_PUBSUB_TOPIC = google_pubsub_topic.slack-message.id,
    _COMPLETION_PUBSUB_TOPIC = google_pubsub_topic.image-updated.id,
    _SERVICE_ACCOUNT_EMAIL = google_service_account.packer.email,
    _SUBNET = google_compute_subnetwork.packer.name,
    _ZONE = var.zone,
  }
}


# Right now Terraform cannot create a CloudBuild trigger that triggers on a
# Pub/Sub message, _and_ that can use GitHub as the source.
# The following GitHub issue tracks this:
# https://github.com/hashicorp/terraform-provider-google/issues/9189
#resource "google_cloudbuild_trigger" "github_main_automated" {
#  depends_on = [
#    google_project_service.cloudbuild
#  ]
#  name = "github-main-automated"
#  description = "Build on a regular schedule, triggered by Pub/Sub"
#
#  github {
#    owner = var.github_owner
#    name = var.github_name
#  }
#  filename = "packer/cloudbuild.yaml"
#
#  pubsub_config {
#    topic = google_pubsub_topic.trigger_build.id
#  }
#
#  substitutions = {
#    _PACKER_DIR = "packer",
#    _SLACK_PUBSUB_TOPIC = google_pubsub_topic.slack-message.id,
#    _COMPLETION_PUBSUB_TOPIC = google_pubsub_topic.image-updated.id,
#    _SERVICE_ACCOUNT_EMAIL = google_service_account.packer.email,
#    _SUBNET = google_compute_subnetwork.packer.name,
#    _ZONE = var.zone,
#  }
#}
