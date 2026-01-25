variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "tf-cicd-pipeline"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "dev-team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# Database Configuration
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "myapp_dev"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "dbadmin"
}

# Application Configuration
variable "app_port" {
  description = "Application port"
  type        = number
  default     = 3000
}

variable "app_cpu" {
  description = "CPU units for ECS task (dev environment)"
  type        = number
  default     = 256
}

variable "app_memory" {
  description = "Memory for ECS task (dev environment)"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Desired number of ECS tasks (dev environment)"
  type        = number
  default     = 1
}

# Development-specific variables
variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown of resources during off-hours"
  type        = bool
  default     = true
}

variable "auto_shutdown_schedule" {
  description = "Cron expression for auto-shutdown (default: 8 PM EST weekdays)"
  type        = string
  default     = "cron(0 1 ? * MON-FRI *)" # 8 PM EST = 1 AM UTC
}

variable "auto_startup_schedule" {
  description = "Cron expression for auto-startup (default: 8 AM EST weekdays)"
  type        = string
  default     = "cron(0 13 ? * MON-FRI *)" # 8 AM EST = 1 PM UTC
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days (dev environment)"
  type        = number
  default     = 7
}

variable "backup_retention_days" {
  description = "Database backup retention in days (dev environment)"
  type        = number
  default     = 7
}

# Monitoring and Alerting
variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = false # Disabled for cost savings in dev
}

variable "alert_email" {
  description = "Email for development alerts"
  type        = string
  default     = "dev-team@company.com"
}

# Security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access development resources"
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] # Private networks only
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for development"
  type        = bool
  default     = false # Disabled for cost savings
}

# Feature flags for development
variable "enable_debug_mode" {
  description = "Enable debug mode for applications"
  type        = bool
  default     = true
}

variable "enable_performance_insights" {
  description = "Enable RDS Performance Insights"
  type        = bool
  default     = false # Disabled for cost savings in dev
}