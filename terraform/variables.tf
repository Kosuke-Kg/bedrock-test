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

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
  default     = "example.com"
}

variable "subdomain" {
  description = "Subdomain for the API"
  type        = string
  default     = "api"
}

variable "db_password" {
  description = "Password for the RDS MySQL database"
  type        = string
  sensitive   = true
}