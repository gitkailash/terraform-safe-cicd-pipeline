terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
    
    # Enable versioning for state file recovery
    versioning = true
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
  database_subnets   = var.database_subnets
  
  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  enable_flow_log        = true
  
  # Production-specific networking
  single_nat_gateway = false # Multiple NAT gateways for HA
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# Production Application Load Balancer with WAF
module "alb" {
  source = "../../modules/alb"
  
  name               = "${var.project_name}-prod-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
  
  enable_deletion_protection = true # Enabled for production
  enable_http2              = true
  enable_cross_zone_load_balancing = true
  
  # SSL/TLS Configuration
  certificate_arn = var.ssl_certificate_arn
  ssl_policy      = "ELBSecurityPolicy-TLS-1-2-2017-01"
  
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
  resource_arn = module.alb.arn
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
  
  # Production-specific settings
  enable_container_insights = true
  capacity_providers        = ["FARGATE"]
  
  # Enhanced monitoring and logging
  enable_execute_command_logging = true
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# Production RDS with Multi-AZ and enhanced security
module "rds" {
  source = "../../modules/rds"
  
  identifier = "${var.project_name}-prod-db"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = var.db_instance_class
  
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_encrypted     = true
  kms_key_id           = aws_kms_key.rds.arn
  
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
  
  # High availability
  multi_az = true
  
  # Enhanced monitoring
  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn
  
  # Performance Insights
  performance_insights_enabled = true
  performance_insights_retention_period = 7
  
  # Security
  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "${var.project_name}-prod-db-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
    Compliance  = "required"
  }
}

# KMS key for RDS encryption
resource "aws_kms_key" "rds" {
  description             = "KMS key for RDS encryption in production"
  deletion_window_in_days = 7
  
  tags = {
    Name        = "${var.project_name}-prod-rds-key"
    Environment = "prod"
    Terraform   = "true"
  }
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.project_name}-prod-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# RDS Enhanced Monitoring Role
resource "aws_iam_role" "rds_monitoring" {
  name = "${var.project_name}-prod-rds-monitoring-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
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

# Production CloudWatch Log Groups with longer retention
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ecs/${var.project_name}-prod"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.logs.arn
  
  tags = {
    Environment = "prod"
    Terraform   = "true"
  }
}

# KMS key for CloudWatch Logs encryption
resource "aws_kms_key" "logs" {
  description             = "KMS key for CloudWatch Logs encryption in production"
  deletion_window_in_days = 7
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
  
  tags = {
    Name        = "${var.project_name}-prod-logs-key"
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
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# KMS key for S3 encryption
resource "aws_kms_key" "s3" {
  description             = "KMS key for S3 encryption in production"
  deletion_window_in_days = 7
  
  tags = {
    Name        = "${var.project_name}-prod-s3-key"
    Environment = "prod"
    Terraform   = "true"
  }
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