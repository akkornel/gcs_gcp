# vim: ts=2 sw=2 et

# INPUTS

variable "account_email" {
    type = string
    description = "The email of the service account"
}

variable "slack_pubsub_topic" {
  type = string
  description = "The Slack Pub/Sub Topic ID"
}

# DATA

# The google_project provider allows us to look up our project ID without it
# needing to be provided to us.
data "google_project" "project" {
}

# IAM

# Allow the https://www.googleapis.com/auth/logging.write scope.
resource "google_project_iam_member" "logging_writer" {
    project = data.google_project.project.project_id
    role = "roles/logging.logWriter"
    member = "serviceAccount:${var.account_email}"
}

# Allow the https://www.googleapis.com/auth/monitoring.write scope.
resource "google_project_iam_member" "monitoring_writer" {
    project = data.google_project.project.project_id
    role = "roles/monitoring.metricWriter"
    member = "serviceAccount:${var.account_email}"
}

# Allow posting Slack messages to Pub/Sub
resource "google_pubsub_topic_iam_member" "pubsub_slack" {
  project = data.google_project.project.project_id
  topic = var.slack_pubsub_topic
  role = "roles/pubsub.publisher"
  member = "serviceAccount:${var.account_email}"
}

# Allow the https://www.googleapis.com/auth/servicecontrol scope.
resource "google_project_iam_member" "servicecontrol" {
    project = data.google_project.project.project_id
    role = "roles/servicemanagement.serviceController"
    member = "serviceAccount:${var.account_email}"
}

# Allow the https://www.googleapis.com/auth/service.management.readonly scope.
resource "google_project_iam_member" "servicemgmt_reporter" {
    project = data.google_project.project.project_id
    role = "roles/servicemanagement.reporter"
    member = "serviceAccount:${var.account_email}"
}

# Allow the https://www.googleapis.com/auth/trace.append scope.
resource "google_project_iam_member" "trace_agent" {
    project = data.google_project.project.project_id
    role = "roles/cloudtrace.agent"
    member = "serviceAccount:${var.account_email}"
}
