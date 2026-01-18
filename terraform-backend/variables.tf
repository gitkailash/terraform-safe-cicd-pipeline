variable "aws_region" {
  description = "AWS region for the backend resources"
  type        = string
  default     = "us-east-1"
}

variable "replica_region" {
  description = "AWS region for cross-region replication"
  type        = string
  default     = "us-west-2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state (must be globally unique)"
  type        = string
  default     = "your-terraform-state-bucket"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.state_bucket_name))
    error_message = "Bucket name must be lowercase, contain only letters, numbers, and hyphens, and not start or end with a hyphen."
  }
}

variable "backup_bucket_name" {
  description = "Name of the S3 bucket for Terraform backups (must be globally unique)"
  type        = string
  default     = "your-terraform-backup-bucket"
  
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.backup_bucket_name))
    error_message = "Bucket name must be lowercase, contain only letters, numbers, and hyphens, and not start or end with a hyphen."
  }
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table for Terraform state locking"
  type        = string
  default     = "terraform-state-lock"
}

variable "enable_cross_region_replication" {
  description = "Enable cross-region replication for disaster recovery"
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Name of the project (used for tagging)"
  type        = string
  default     = "myapp"
}

variable "environment" {
  description = "Environment name (used for tagging)"
  type        = string
  default     = "shared"
}

variable "owner" {
  description = "Owner of the resources (used for tagging)"
  type        = string
  default     = "devops-team"
}

variable "cost_center" {
  description = "Cost center for billing (used for tagging)"
  type        = string
  default     = "infrastructure"
}