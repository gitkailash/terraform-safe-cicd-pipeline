# Development Environment Outputs

# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# ALB Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "alb_arn" {
  description = "ARN of the Application Load Balancer"
  value       = module.alb.alb_arn
}

output "target_group_arn" {
  description = "ARN of the ALB target group"
  value       = module.alb.target_group_arn
}

# ECS Outputs
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = module.ecs.cluster_arn
}

output "ecs_security_group_id" {
  description = "ID of the ECS security group"
  value       = module.ecs.security_group_id
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = module.rds.db_instance_endpoint
}

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.db_instance_id
}

output "rds_port" {
  description = "RDS instance port"
  value       = module.rds.db_instance_port
}

# S3 Outputs
output "assets_bucket_name" {
  description = "Name of the assets S3 bucket"
  value       = aws_s3_bucket.assets.bucket
}

output "assets_bucket_arn" {
  description = "ARN of the assets S3 bucket"
  value       = aws_s3_bucket.assets.arn
}

# CloudWatch Outputs
output "log_group_name" {
  description = "Name of the CloudWatch log group"
  value       = aws_cloudwatch_log_group.app_logs.name
}

# Security Group Outputs
output "alb_security_group_id" {
  description = "ID of the ALB security group"
  value       = aws_security_group.alb.id
}

output "rds_security_group_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds.id
}

# Lambda Outputs (if auto-shutdown is enabled)
output "auto_shutdown_function_name" {
  description = "Name of the auto-shutdown Lambda function"
  value       = aws_lambda_function.auto_shutdown.function_name
}

output "auto_shutdown_function_arn" {
  description = "ARN of the auto-shutdown Lambda function"
  value       = aws_lambda_function.auto_shutdown.arn
}