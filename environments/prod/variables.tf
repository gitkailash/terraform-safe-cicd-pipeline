# Production Environment Variables

variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "AWS CLI profile to use"
  type        = string
  default     = "default"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "tf-cicd-pipeline"
}

variable "owner" {
  description = "Owner of the resources"
  type        = string
  default     = "prod-team"
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
  default     = "10.1.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24", "10.1.3.0/24"]
}

variable "private_subnets" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.20.0/24", "10.1.30.0/24"]
}

# Database Configuration
variable "db_name" {
  description = "Database name"
  type        = string
  default     = "myapp_prod"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "dbadmin"
}

variable "db_instance_class" {
  description = "RDS instance class for production"
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "Initial allocated storage for RDS"
  type        = number
  default     = 100
}

variable "db_max_allocated_storage" {
  description = "Maximum allocated storage for RDS"
  type        = number
  default     = 1000
}

variable "backup_retention_days" {
  description = "Database backup retention in days (production)"
  type        = number
  default     = 30
}

# Application Configuration
variable "app_port" {
  description = "Application port"
  type        = number
  default     = 3000
}

variable "app_cpu" {
  description = "CPU units for ECS task (production)"
  type        = number
  default     = 1024
}

variable "app_memory" {
  description = "Memory for ECS task (production)"
  type        = number
  default     = 2048
}

variable "desired_count" {
  description = "Desired number of ECS tasks (production)"
  type        = number
  default     = 3
}

# SSL Configuration
variable "ssl_certificate_arn" {
  description = "ARN of SSL certificate for HTTPS"
  type        = string
  default     = ""
}

# Monitoring and Alerting
variable "log_retention_days" {
  description = "CloudWatch log retention in days (production)"
  type        = number
  default     = 90
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed CloudWatch monitoring"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email for production alerts"
  type        = string
  default     = "prod-alerts@company.com"
}

# Security
variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access production resources"
  type        = list(string)
  default     = ["10.0.0.0/8"] # Only private networks
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs for production"
  type        = bool
  default     = true
}

# Compliance and Backup
variable "enable_encryption" {
  description = "Enable encryption for all resources"
  type        = bool
  default     = true
}

variable "compliance_mode" {
  description = "Enable compliance mode with additional security controls"
  type        = bool
  default     = true
}