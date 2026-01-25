terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  backend "s3" {
    bucket         = "terraform-safe-cicd-pipeline-2026"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Environment   = "dev"
      Project       = var.project_name
      ManagedBy     = "terraform"
      Owner         = var.owner
      CostCenter    = var.cost_center
      BackupPolicy  = "dev-backup"
    }
  }
}

# Data sources for existing resources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Example VPC module usage
module "vpc" {
  source = "../../modules/vpc"
  
  environment = "dev"
  vpc_cidr    = var.vpc_cidr
  
  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  
  enable_nat_gateway = true
  enable_vpn_gateway = false
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Example application load balancer
module "alb" {
  source = "../../modules/alb"
  
  name               = "${var.project_name}-dev-alb"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [aws_security_group.alb.id]
  
  enable_deletion_protection = false # Disabled for dev environment
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Security group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-dev-alb-"
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
    Name        = "${var.project_name}-dev-alb-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# Example ECS cluster for development
module "ecs" {
  source = "../../modules/ecs"
  
  cluster_name = "${var.project_name}-dev"
  environment  = "dev"
  vpc_id       = module.vpc.vpc_id
  
  # Development-specific settings
  enable_container_insights = true
  capacity_providers        = ["FARGATE", "FARGATE_SPOT"]
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Development database (smaller instance)
module "rds" {
  source = "../../modules/rds"
  
  identifier = "${var.project_name}-dev-db"
  
  engine         = "postgres"
  engine_version = "15.4"
  instance_class = "db.t3.micro" # Small instance for dev
  
  allocated_storage     = 20
  max_allocated_storage = 100
  
  db_name  = var.db_name
  username = var.db_username
  
  # Get password from AWS Secrets Manager
  manage_master_user_password = true
  
  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  
  backup_retention_period = 7  # Shorter retention for dev
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"
  
  skip_final_snapshot = true # Skip final snapshot for dev
  deletion_protection = false
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Security group for RDS
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-dev-rds-"
  vpc_id      = module.vpc.vpc_id
  
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [module.ecs.security_group_id]
  }
  
  tags = {
    Name        = "${var.project_name}-dev-rds-sg"
    Environment = "dev"
    Terraform   = "true"
  }
}

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/aws/ecs/${var.project_name}-dev"
  retention_in_days = 7 # Shorter retention for dev
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Development-specific S3 bucket for assets
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-dev-assets-${random_id.bucket_suffix.hex}"
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
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

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Cost optimization: Auto-shutdown for dev resources
resource "aws_lambda_function" "auto_shutdown" {
  filename         = "auto_shutdown.zip"
  function_name    = "${var.project_name}-dev-auto-shutdown"
  role            = aws_iam_role.lambda_role.arn
  handler         = "index.handler"
  runtime         = "python3.9"
  timeout         = 60
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-dev-lambda-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}