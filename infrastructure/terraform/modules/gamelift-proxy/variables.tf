variable "project_name" {
  description = "Prefix for resource names."
  type        = string
  default     = "frontendui"
}

variable "fleet_id" {
  description = "GameLift fleet id (fleet-... or containerfleet-...) pinned onto every request. Empty = client chooses."
  type        = string
  default     = ""
}

variable "alias_id" {
  description = "GameLift alias id pinned onto every request (takes precedence over fleet_id)."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "throttle_rate" {
  description = "Steady-state requests/second allowed through the API."
  type        = number
  default     = 20
}

variable "throttle_burst" {
  type    = number
  default = 50
}

variable "auth_mode" {
  description = "Player authentication: \"none\" (anyone with the URL) or \"eos\" (Bearer Epic access token, introspected with Epic tokenInfo)."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["none", "eos"], var.auth_mode)
    error_message = "auth_mode must be \"none\" or \"eos\"."
  }
}

variable "eos_client_id" {
  description = "EOS Client ID the player tokens must have been issued for (required when auth_mode = eos)."
  type        = string
  default     = ""
}

variable "eos_client_secret_ssm_parameter" {
  description = "Optional SSM SecureString parameter name (e.g. /frontendui/eos/client_secret) used for Basic auth on tokenInfo."
  type        = string
  default     = ""
}

variable "queue_name" {
  description = "Game session queue (name or ARN) pinned onto StartGameSessionPlacement. Empty = client chooses."
  type        = string
  default     = ""
}
