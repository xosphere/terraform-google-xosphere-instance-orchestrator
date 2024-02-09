# enable APIs
locals {
  version           = "0.1.0"
  xo_account_region = "us-west1"
  xo_project_id     = "io-backend-prod"
  endpoint_url      = "https://portal-api.xosphere.io"
  releases_bucket   = "xosphere-io-releases"
  regions           = join(",", var.regions_enabled)
  api_token_path    = format("projects/%s/secrets/customer_token__%s", local.xo_project_id, var.customer_id)
  xo_support_project_id = "xosphere-io-support"



  services = toset([
    "storage-component.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "run.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "compute.googleapis.com",
  ])
}

resource "google_project_service" "project" {
  for_each = local.services
  project  = var.project_id
  service  = each.key

  timeouts {
    create = "30m"
    update = "40m"
  }
}

locals {
  permissions_list = [
    "resourcemanager.projects.get",
    "compute.instanceTemplates.list",
    "compute.instanceGroupManagers.list",
    "compute.autoscalers.list",
    "compute.autoscalers.get",
    "compute.instanceGroupManagers.get",
    "compute.instanceTemplates.create",
    "compute.subnetworks.get",
    "compute.instanceGroupManagers.update",
    "compute.instanceTemplates.useReadOnly",
    "compute.instanceTemplates.get",
    "compute.instances.create",
    "compute.disks.create",
    "compute.subnetworks.use",
    "compute.instances.setMetadata",
    "compute.instances.setLabels",
    "compute.instances.list",
  ]
}

# role
resource "google_project_iam_custom_role" "xosphere_instance_orchestrator" {
  count       = var.iam_bindings_type == "project" ? 1 : 0
  role_id     = "xosphere_instance_orchestrator"
  title       = "Xosphere Instance Orchestrator"
  description = "Role for Xosphere Instance Orchestrator"
  permissions = local.permissions_list
}

resource "google_organization_iam_custom_role" "xosphere_instance_orchestrator" {
  count       = (var.iam_bindings_type == "organization" || var.iam_bindings_type == "folder") ? 1 : 0
  org_id      = var.organization_id
  role_id     = "xosphere_instance_orchestrator"
  title       = "Xosphere Instance Orchestrator"
  description = "Role for Xosphere Instance Orchestrator"
  permissions = local.permissions_list
}

# service account
resource "google_service_account" "xosphere_instance_orchestrator_service_account" {
  account_id   = "xosphere-instance-orchestrator"
  display_name = "Xosphere Instance Orchestrator"
}

# logging config
resource "google_logging_project_bucket_config" "logging_config" {
    project          = var.project_id
    location         = var.install_region
    retention_days   = var.log_retention
    enable_analytics = false
    bucket_id        = "xosphere-io-logs"
}

resource "google_logging_project_sink" "logging_sink" {
  name = "xosphere-logs-sink"
  destination = "logging.googleapis.com/${google_logging_project_bucket_config.logging_config.id}"
  unique_writer_identity = true
  filter = "(resource.type = \"cloud_run_revision\" AND resource.labels.service_name =~ \"^xosphere-*\") OR (resource.type = \"cloud_scheduler_job\" AND resource.labels.job_id =~ \"^xosphere-*\")"
}

# bindings
resource "google_organization_iam_member" "xosphere_instance_orchestrator_service_account_organization_binding" {
  count  = var.iam_bindings_type == "organization" ? 1 : 0
  org_id = var.organization_id
  role   = google_organization_iam_custom_role.xosphere_instance_orchestrator[0].id
  member = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

resource "google_organization_iam_member" "xosphere_instance_orchestrator_service_account_organization_binding_sa_user" {
  count  = var.iam_bindings_type == "organization" ? 1 : 0
  org_id = var.organization_id
  role   = "roles/iam.serviceAccountUser"
  member = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

resource "google_folder_iam_member" "xosphere_instance_orchestrator_service_account_folder_binding" {
  count  = var.iam_bindings_type == "folder" ? 1 : 0
  folder = var.iam_binding_folder
  role   = google_organization_iam_custom_role.xosphere_instance_orchestrator[0].id
  member = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

resource "google_folder_iam_member" "xosphere_instance_orchestrator_service_account_folder_binding_sa_user" {
  count  = var.iam_bindings_type == "folder" ? 1 : 0
  folder = var.iam_binding_folder
  role   = "roles/iam.serviceAccountUser"
  member = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

resource "google_project_iam_member" "xosphere_instance_orchestrator_service_account_project_binding" {
  count   = var.iam_bindings_type == "project" ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.xosphere_instance_orchestrator[0].id
  member  = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

resource "google_project_iam_member" "xosphere_instance_orchestrator_service_account_project_binding_sa_user" {
  count   = var.iam_bindings_type == "project" ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}

# cloud function
resource "google_cloudfunctions2_function" "xosphere_instance_orchestrator_function" {
  name     = "xosphere-instance-orchestrator-function"
  project  = var.project_id
  location = var.install_region

  build_config {
    runtime     = "go121"
    entry_point = "handlerHttp"
    source {
      storage_source {
        bucket = local.releases_bucket
        object = "instance-orchestrator/${local.version}/orchestrator.zip"
      }
    }
  }

  service_config {
    service_account_email = google_service_account.xosphere_instance_orchestrator_service_account.email

    ingress_settings                 = "ALLOW_INTERNAL_ONLY"
    available_cpu                    = var.function_cpu
    available_memory                 = var.function_memory_size
    max_instance_request_concurrency = 1
    min_instance_count               = 0
    max_instance_count               = 1
    timeout_seconds                  = var.function_timeout
    environment_variables = {
      "TIMEOUT_IN_SECS" : var.function_timeout
      "INSTALLED_REGION" : var.install_region
      "INSTALLED_PROJECT" : var.project_id
      "API_TOKEN_PATH" : local.api_token_path
      "ENDPOINT_URL" : local.endpoint_url
      "INSTANCE_STATE_BUCKET" : google_storage_bucket.instance_state_bucket.name
      "REGIONS" : local.regions
      "PROJECT_ENABLED_LABEL_SUFFIX" : var.enabled_label_suffix
    }
  }
}

# state bucket
resource "google_storage_bucket" "instance_state_bucket" {
  name                        = "xosphere-instance-orchestrator-state-${var.project_id}"
  location                    = var.install_region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
}

resource "google_storage_bucket_iam_member" "instance_state_bucket_owner" {
  bucket = google_storage_bucket.instance_state_bucket.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_service_account.email}"
}


# cloud function trigger via cloud scheduler
resource "google_service_account" "xosphere_instance_orchestrator_invoker" {
  account_id   = "xosphere-io-invoker"
  display_name = "Xosphere Instance Orchestrator Invoker"
}

resource "google_cloudfunctions2_function_iam_member" "xosphere_instance_orchestrator_invoker" {
  project        = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.project
  location       = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.location
  cloud_function = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.name
  role           = "roles/cloudfunctions.invoker"
  member         = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_invoker.email}"
}

resource "google_cloud_run_service_iam_member" "xosphere_instance_orchestrator_invoker" {
  project  = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.project
  location = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.location
  service  = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.xosphere_instance_orchestrator_invoker.email}"
}

resource "google_cloud_scheduler_job" "xosphere_instance_orchestrator_invoker" {
  name        = "xosphere-instance-orchestrator-invoker"
  description = "Xosphere Instance Orchestrator Invoker"
  schedule    = var.function_cron_schedule
  project     = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.project
  region      = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.location
  retry_config {
    retry_count = 3
  }

  http_target {
    uri         = google_cloudfunctions2_function.xosphere_instance_orchestrator_function.service_config[0].uri
    http_method = "POST"
    body        = base64encode("{}")
    headers = {
      "Content-Type" = "application/json"
    }
    oidc_token {
      audience              = "${google_cloudfunctions2_function.xosphere_instance_orchestrator_function.service_config[0].uri}/"
      service_account_email = google_service_account.xosphere_instance_orchestrator_invoker.email
    }
  }
}

# auto support
resource "google_project_iam_member" "xosphere_instance_orchestrator_support_binding_logs" {
  count = var.enable_auto_support > 0 ? 1 : 0

  project = var.project_id
  role   = "roles/logging.privateLogViewer"
  member  = "serviceAccount:xosphere-io-auto-support@${local.xo_support_project_id}.iam.gserviceaccount.com"
  condition {
    title       = "xosphere-support-logs"
    description = "xosphere-support-logs"
    expression  = "resource.name.startsWith(\"${google_logging_project_bucket_config.logging_config.id}\")"
  }
}

resource "google_project_iam_custom_role" "auto_support" {
  count       = var.enable_auto_support > 0 && var.iam_bindings_type == "project" ? 1 : 0
  role_id     = "xosphere_auto_support"
  title       = "Xosphere Auto Support"
  description = "Role for Xosphere Auto Support"
  permissions = [
    "resourcemanager.projects.get",
    "compute.instanceTemplates.list",
    "compute.instanceGroupManagers.list",
    "compute.autoscalers.list",
    "compute.instanceGroupManagers.get",
    "compute.subnetworks.get",
    "compute.instanceTemplates.useReadOnly",
    "compute.instanceTemplates.get",
  ]
}

resource "google_organization_iam_custom_role" "auto_support" {
  count       = var.enable_auto_support > 0 && (var.iam_bindings_type == "organization" || var.iam_bindings_type == "folder") ? 1 : 0
  org_id      = var.organization_id
  role_id     = "xosphere_auto_support"
  title       = "Xosphere Auto Support"
  description = "Role for Xosphere Auto Support"
  permissions = [
    "compute.autoscalers.list",
    "compute.instanceGroups.list",
    "compute.instanceGroupManagers.get",
    "compute.instanceGroupManagers.list",
    "compute.instanceTemplates.list",
    "compute.instanceTemplates.get",
    "compute.subnetworks.get",
    "resourcemanager.projects.get",
  ]
}

# bindings
resource "google_organization_iam_member" "auto_support_organization_binding" {
  count  = var.enable_auto_support > 0 && var.iam_bindings_type == "organization" ? 1 : 0
  org_id = var.organization_id
  role   = google_organization_iam_custom_role.auto_support[0].id
  member = "serviceAccount:xosphere-io-auto-support@${local.xo_support_project_id}.iam.gserviceaccount.com"
}

resource "google_folder_iam_member" "auto_support_folder_binding" {
  count  = var.enable_auto_support > 0 && var.iam_bindings_type == "folder" ? 1 : 0
  folder = var.iam_binding_folder
  role   = google_organization_iam_custom_role.auto_support[0].id
  member = "serviceAccount:xosphere-io-auto-support@${local.xo_support_project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "auto_support_project_binding" {
  count   = var.enable_auto_support > 0 && var.iam_bindings_type == "project" ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.auto_support[0].id
  member  = "serviceAccount:xosphere-io-auto-support@${local.xo_support_project_id}.iam.gserviceaccount.com"
}
