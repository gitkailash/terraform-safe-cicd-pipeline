# Terraform Backend Infrastructure
# This file creates the S3 bucket and DynamoDB table for Terraform state management
# Run this FIRST before setting up the main infrastructure

terraform {
  required_version = ">= 1.6.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
  # This backend configuration is intentionally local for bootstrapping
  # After creating the S3 bucket, migrate this to use the remote backend
}

provider "aws" {
  region = var.aws_region
  
  default_tags {
    tags = {
      Project     = "terraform-backend"
      ManagedBy   = "terraform"
      Environment = "shared"
      Purpose     = "state-management"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# S3 bucket for Terraform state
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name
  
  tags = {
    Name        = "Terraform State Bucket"
    Description = "Stores Terraform state files for all environments"
  }
}

# Enable versioning for state file recovery
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_state.arn
    }
    bucket_key_enabled = true
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle configuration for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  
  rule {
    id     = "state_file_lifecycle"
    status = "Enabled"
    
    # Keep current versions
    expiration {
      days = 0  # Never expire current versions
    }
    
    # Manage non-current versions
    noncurrent_version_expiration {
      noncurrent_days = 90  # Keep 90 days of old versions
    }
    
    # Transition old versions to cheaper storage
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    
    noncurrent_version_transition {
      noncurrent_days = 60
      storage_class   = "GLACIER"
    }
  }
}

# KMS key for S3 encryption
resource "aws_kms_key" "terraform_state" {
  description             = "KMS key for Terraform state bucket encryption"
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
        Sid    = "Allow Terraform State Access"
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-terraform-dev",
            "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/github-actions-terraform-prod"
          ]
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
    Name = "terraform-state-key"
  }
}

resource "aws_kms_alias" "terraform_state" {
  name          = "alias/terraform-state"
  target_key_id = aws_kms_key.terraform_state.key_id
}

# DynamoDB table for state locking
resource "aws_dynamodb_table" "terraform_locks" {
  name           = var.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "LockID"
  
  attribute {
    name = "LockID"
    type = "S"
  }
  
  # Enable point-in-time recovery
  point_in_time_recovery {
    enabled = true
  }
  
  # Server-side encryption
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }
  
  tags = {
    Name        = "Terraform State Locks"
    Description = "DynamoDB table for Terraform state locking"
  }
}

# KMS key for DynamoDB encryption
resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for DynamoDB Terraform locks table"
  deletion_window_in_days = 7
  
  tags = {
    Name = "terraform-locks-key"
  }
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/terraform-locks"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# S3 bucket for backups
resource "aws_s3_bucket" "terraform_backups" {
  bucket = var.backup_bucket_name
  
  tags = {
    Name        = "Terraform Backups Bucket"
    Description = "Stores Terraform state backups and recovery files"
  }
}

resource "aws_s3_bucket_versioning" "terraform_backups" {
  bucket = aws_s3_bucket.terraform_backups.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_backups" {
  bucket = aws_s3_bucket.terraform_backups.id
  
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_backups.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_backups" {
  bucket = aws_s3_bucket.terraform_backups.id
  
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Cross-region replication for disaster recovery
resource "aws_s3_bucket_replication_configuration" "terraform_backups" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  role   = aws_iam_role.replication[0].arn
  bucket = aws_s3_bucket.terraform_backups.id
  
  rule {
    id     = "replicate_backups"
    status = "Enabled"
    
    destination {
      bucket        = aws_s3_bucket.terraform_backups_replica[0].arn
      storage_class = "STANDARD_IA"
      
      encryption_configuration {
        replica_kms_key_id = aws_kms_key.terraform_backups_replica[0].arn
      }
    }
  }
  
  depends_on = [aws_s3_bucket_versioning.terraform_backups]
}

# Replica bucket in different region
resource "aws_s3_bucket" "terraform_backups_replica" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  provider = aws.replica
  bucket   = "${var.backup_bucket_name}-replica"
  
  tags = {
    Name        = "Terraform Backups Replica"
    Description = "Cross-region replica of Terraform backups"
  }
}

# KMS keys for backup encryption
resource "aws_kms_key" "terraform_backups" {
  description             = "KMS key for Terraform backups bucket encryption"
  deletion_window_in_days = 7
  
  tags = {
    Name = "terraform-backups-key"
  }
}

resource "aws_kms_key" "terraform_backups_replica" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  provider                = aws.replica
  description             = "KMS key for Terraform backups replica bucket encryption"
  deletion_window_in_days = 7
  
  tags = {
    Name = "terraform-backups-replica-key"
  }
}

# IAM role for cross-region replication
resource "aws_iam_role" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  name = "terraform-s3-replication-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_policy" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  name = "terraform-s3-replication-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl"
        ]
        Resource = "${aws_s3_bucket.terraform_backups.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.terraform_backups.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete"
        ]
        Resource = "${aws_s3_bucket.terraform_backups_replica[0].arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  count = var.enable_cross_region_replication ? 1 : 0
  
  role       = aws_iam_role.replication[0].name
  policy_arn = aws_iam_policy.replication[0].arn
}

# CloudWatch alarms for monitoring
resource "aws_cloudwatch_metric_alarm" "state_bucket_errors" {
  alarm_name          = "terraform-state-bucket-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xxErrors"
  namespace           = "AWS/S3"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "This metric monitors S3 4xx errors for Terraform state bucket"
  
  dimensions = {
    BucketName = aws_s3_bucket.terraform_state.bucket
  }
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# SNS topic for alerts
resource "aws_sns_topic" "alerts" {
  name = "terraform-backend-alerts"
  
  tags = {
    Name = "Terraform Backend Alerts"
  }
}

# Output important values
output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform state"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table for state locking"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket for backups"
  value       = aws_s3_bucket.terraform_backups.bucket
}

output "kms_key_arn" {
  description = "ARN of the KMS key for state encryption"
  value       = aws_kms_key.terraform_state.arn
}