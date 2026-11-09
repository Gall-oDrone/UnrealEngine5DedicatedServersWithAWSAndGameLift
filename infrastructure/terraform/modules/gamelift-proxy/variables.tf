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
