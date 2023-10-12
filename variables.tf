# Xosphere Instance Orchestration configuration
variable "customer_id" {}
variable "organization_id" {}
variable "project_id" {}
variable "install_region" {}

variable "iam_bindings_type" {
  description = "The type of object specified in iam_bindings_resource.  Valid options: organization, folder, project"
  default     = "organization"
  validation {
    condition     = contains(["organization", "folder", "project"], var.iam_bindings_type)
    error_message = "Allowed values for iam_bindings_type are \"organization\", \"folder\", \"project\"."
  }
}

variable "iam_binding_folder" {
  description = "The folder ID to attach IAM bindings.  Only needed if iam_bindings_type is set to \"folder\""
  default     = null
}

variable "projects_enabled_default" {
  type        = bool
  description = "If non-attributed projects should be considered Enabled"
  default     = true
}

variable "enabled_label_suffix" {
  description = "Suffix for enabled label"
  default     = ""
}

variable "regions_enabled" {
  description = "Regions enabled for Instance Orchestrator"
  default     = ["us-east1", "us-west1"]
}

variable "function_memory_size" {
  description = "Memory size allocated"
  default     = "1Gi"
}

variable "function_cpu" {
  description = "CPU allocated"
  default     = null
}

variable "function_timeout" {
  description = "Function execution timeout"
  default     = 120
}

variable "function_cron_schedule" {
  description = "Function schedule cron expression"
  default     = "* * * * *"
}

variable "log_retention" {
  description = "Lambda function log file retention in days"
  default = 30
}

variable "enable_auto_support" {
  description = "Enable Auto Support"
  default     = 1
}
