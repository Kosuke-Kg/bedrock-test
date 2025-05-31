variable "environment" {
  description = "environment name"
  type        = string
  default     = "stg"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}
