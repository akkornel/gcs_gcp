# vim: ts=2 sw=2 et

# FUNCTION: Image Cleanup

resource "google_storage_bucket_object" "cleanup" {
  bucket = google_storage_bucket.cloudbuild-data.name
  name = "functions/cleanup.zip"
  source = "../functions/cleanup/.archive.zip"
  content_type = "application/zip"
}

resource "google_cloudfunctions_function" "cleanup" {
  region = var.cloudfunctions_region
  name = "cleanup"
  description = "When a new image is created, diff it to the previous image, and clean up older images."

  runtime = "python39"
  source_archive_bucket = google_storage_bucket.cloudbuild-data.name
  source_archive_object = google_storage_bucket_object.cleanup.name
  entry_point = "handle_event"

  available_memory_mb = 256
  timeout = 180

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.image-updated.name
    failure_policy {
      retry = false
    }
  }

  environment_variables = {
    LOG_LEVEL = "DEBUG",
    SLACK_MESSAGE_TOPIC = google_pubsub_topic.slack-message.id
  }

  depends_on = [
    google_project_iam_member.cloudfunctions-storage-functions-read,
    google_pubsub_topic_iam_member.cloudfunctions-iam-subscribe-image,
    google_pubsub_topic_iam_member.cloudfunctions-iam-post
  ]
}

# FUNCTION: Update Templates

resource "google_storage_bucket_object" "template" {
  bucket = google_storage_bucket.cloudbuild-data.name
  name = "functions/template.zip"
  source = "../functions/template/.archive.zip"
  content_type = "application/zip"
}

resource "google_cloudfunctions_function" "template" {
  region = var.cloudfunctions_region
  name = "template"
  description = "When a new image is created, update Compute Engine templates to point to the new image."

  runtime = "python39"
  source_archive_bucket = google_storage_bucket.cloudbuild-data.name
  source_archive_object = google_storage_bucket_object.template.name
  entry_point = "handle_event"

  available_memory_mb = 256
  timeout = 180

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.image-updated.name
    failure_policy {
      retry = false
    }
  }

  environment_variables = {
    LOG_LEVEL = "DEBUG",
    SLACK_MESSAGE_TOPIC = google_pubsub_topic.slack-message.id,
    TEMPLATE_NAMES = "gcs-dtn, gcs-management",
  }

  depends_on = [
    google_project_iam_member.cloudfunctions-storage-functions-read,
    google_pubsub_topic_iam_member.cloudfunctions-iam-subscribe-image,
    google_pubsub_topic_iam_member.cloudfunctions-iam-post
  ]
}

# FUNCTION: Slack Message

resource "google_storage_bucket_object" "slack-message" {
  bucket = google_storage_bucket.cloudbuild-data.name
  name = "functions/slack_message.zip"
  source = "../functions/slack_message/.archive.zip"
  content_type = "application/zip"
}

resource "google_cloudfunctions_function" "slack-message" {
  region = var.cloudfunctions_region
  name = "slack-message"
  description = "Post a Slack message from Pub/Sub"

  runtime = "python39"
  entry_point = "handle_event"
  source_archive_bucket = google_storage_bucket.cloudbuild-data.name
  source_archive_object = google_storage_bucket_object.slack-message.name

  available_memory_mb = 128
  timeout = 20

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource = google_pubsub_topic.slack-message.id
    failure_policy {
      retry = true
    }
  }

  environment_variables = {
    LOG_LEVEL = "DEBUG",
    SLACK_WEBHOOK_SECRET = "${google_secret_manager_secret.slack-webhook.id}/versions/latest"
  }

  depends_on = [
    google_project_iam_member.cloudfunctions-storage-functions-read,
    google_pubsub_topic_iam_member.cloudfunctions-iam-subscribe-slack,
    google_secret_manager_secret_version.slack-webhook
  ]
}

# IAM

# Give Cloud Functions permissions to listen to image_updated messages
resource "google_pubsub_topic_iam_member" "cloudfunctions-iam-subscribe-image" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.image-updated.name
  role = "roles/pubsub.subscriber"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# Give Cloud Functions permissions to publish Slack messages
resource "google_pubsub_topic_iam_member" "cloudfunctions-iam-post" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.slack-message.name
  role = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# Give Cloud Functions permissions to listen to Slack messages
resource "google_pubsub_topic_iam_member" "cloudfunctions-iam-subscribe-slack" {
  project = data.google_project.project.project_id
  topic = google_pubsub_topic.slack-message.name
  role = "roles/pubsub.subscriber"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# Give Cloud Functions permissions to read functions source
resource "google_project_iam_member" "cloudfunctions-storage-functions-read" {
  project = data.google_project.project.project_id
  role = "roles/storage.objectViewer"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
  condition {
    title = "Cloud Functions may read from functions storage"
    description = "This is where the source archives for Cloud Functions live."
    expression = <<EOT
resource.name.startsWith("projects/_/buckets/uit-uit-et-globusmigrate-dev_cloudbuild/objects/functions/")
EOT
  }
}

# Give Cloud Functions permissions to read the Slack Webhook URL.
resource "google_secret_manager_secret_iam_member" "cloudfunctions-secret-slack-read" {
  project = data.google_project.project.project_id
  secret_id = google_secret_manager_secret.slack-webhook.secret_id
  role = "roles/secretmanager.secretAccessor"
  member = "serviceAccount:${data.google_app_engine_default_service_account.default.email}"
}

# SECRETS

# Store the Slack Webhook URL in a Secret.
resource "google_secret_manager_secret" "slack-webhook" {
  secret_id = "slack_webhook"

  replication {
    automatic = true
  }
}

resource "google_secret_manager_secret_version" "slack-webhook" {
  secret = google_secret_manager_secret.slack-webhook.id

  secret_data = var.slack_webhook
}
