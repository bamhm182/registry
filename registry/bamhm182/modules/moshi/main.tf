terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

locals {
  icon_url = "/emojis/1f43e.png"
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log Moshi to."
  default     = "/tmp/moshi.log"
}

variable "port" {
  type        = number
  description = "Moshi test port"
  default     = 24543
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

resource "coder_script" "moshi" {
  agent_id     = var.agent_id
  display_name = "Moshi"
  icon         = local.icon_url
  script = templatefile("${path.module}/scripts/run.sh", {
    LOG_PATH : var.log_path
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "moshi" {
  agent_id     = var.agent_id
  slug         = "moshi"
  display_name = "Moshi"
  url          = "http://localhost:${var.port}"
  icon         = local.icon_url
  subdomain    = false
  share        = "owner"
  order        = var.order
}