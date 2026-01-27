terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment   = "prod"
      Project       = var.project_name
      ManagedBy     = "terraform"
      Owner         = var.owner
      CostCenter    = var.cost_center
      BackupPolicy  = "prod-backup"
      Compliance    = "required"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Production VPC with enhanced security
module "vpc" {
  source = "../../modules/vpc"
  
  environment = "prod"
  vpc_cidr    = var.vpc_cidr
  
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# Production Application Load Balancer
module "alb" {
  source = "../../modules/alb"
  
  name               = "${var.project_name}-prod-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
  
  enable_deletion_protection = true # Enabled for production
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# WAF for production ALB
resource "aws_wafv2_web_acl" "main" {
  name  = "${var.project_name}-prod-waf"
  scope = "REGIONAL"
  
  default_action {
    allow {}
  }
  
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}ProdWAF"
    sampled_requests_enabled   = true
  }
  
  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 1
    
    action {
      block {}
    }
    
    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitRule"
      sampled_requests_enabled   = true
    }
  }
  
  # AWS Managed Rules
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 2
    
    override_action {
      none {}
    }
    
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = module.alb.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# Production ALB Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-prod-alb-"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name        = "${var.project_name}-prod-alb-sg"
    Environment = "prod"
    Terraform   = "true"
  }
}

# Production ECS Cluster with enhanced monitoring
module "ecs" {
  source = "../../modules/ecs"
  
  cluster_name = "${var.project_name}-prod"
  environment  = "prod"
  vpc_id       = module.vpc.vpc_id
  
  # Production-specific settings
  enable_container_insights = true
  capacity_providers        = ["FARGATE"]
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# Production RDS with enhanced security
module "rds" {
  source = "../../modules/rds"
  
  identifier = "${var.project_name}-prod-db"
  
  engine         = "postgres"
  engine_version = "15.8"
  instance_class = var.db_instance_class
  
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  
  db_name  = var.db_name
  username = var.db_username
  
  # Enhanced security for production
  manage_master_user_password = true
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  
  # Production backup and maintenance settings
  backup_retention_period = var.backup_retention_days
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  # Security
  deletion_protection = true
  skip_final_snapshot = false
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# Production RDS Security Group
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-prod-rds-"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.ecs.security_group_id]
  }
  
  tags = {
    Name        = "${var.project_name}-prod-rds-sg"
    Environment = "prod"
    Terraform   = "true"
  }
}

# Production CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ecs/${var.project_name}-prod"
  retention_in_days = var.log_retention_days
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

# Production S3 bucket with enhanced security
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-prod-assets-${random_id.bucket_suffix.hex}"
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# CloudWatch Alarms for production monitoring
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${var.project_name}-prod-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "This metric monitors ECS CPU utilization"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  
  dimensions = {
    ClusterName = module.ecs.cluster_name
  }
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

# SNS topic for production alerts
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-prod-alerts"
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}