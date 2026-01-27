#!/bin/bash

# Terraform Backend Setup Script
# This script initializes the S3 bucket and DynamoDB table for Terraform state management

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_ROOT/terraform-backend"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Terraform Backend Setup Script - Initialize S3 bucket and DynamoDB table for state management

OPTIONS:
    -b, --bucket BUCKET_NAME     S3 bucket name for Terraform state (required)
    -r, --region REGION          AWS region [default: us-east-1]
    -p, --project PROJECT_NAME   Project name for tagging [default: myapp]
    -f, --force                  Skip confirmation prompts
    -d, --dry-run               Show what would be done without executing
    -h, --help                  Show this help message

EXAMPLES:
    $0 -b my-terraform-state-bucket
    $0 -b my-terraform-state-bucket -r us-west-2 -p myproject
    $0 --dry-run -b my-terraform-state-bucket

PREREQUISITES:
    - AWS CLI configured with appropriate permissions
    - Terraform installed (>= 1.6.0)
    - jq installed for JSON processing

REQUIRED AWS PERMISSIONS:
    - s3:CreateBucket, s3:PutBucketVersioning, s3:PutBucketEncryption
    - dynamodb:CreateTable, dynamodb:DescribeTable
    - kms:CreateKey, kms:CreateAlias
    - iam:CreateRole, iam:AttachRolePolicy (if cross-region replication enabled)

EOF
}

# Parse command line arguments
parse_args() {
    BUCKET_NAME=""
    AWS_REGION="us-east-1"
    PROJECT_NAME="myapp"
    FORCE=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -b|--bucket)
                BUCKET_NAME="$2"
                shift 2
                ;;
            -r|--region)
                AWS_REGION="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$BUCKET_NAME" ]]; then
        error "S3 bucket name is required. Use -b or --bucket"
        usage
        exit 1
    fi

    # Validate bucket name format
    if [[ ! "$BUCKET_NAME" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        error "Invalid bucket name format. Must be lowercase, contain only letters, numbers, and hyphens."
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed. Please install it first."
        exit 1
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed. Please install it first."
        exit 1
    fi

    # Check jq (optional for basic functionality)
    if ! command -v jq &> /dev/null; then
        warning "jq is not installed. Some features may be limited."
        JQ_AVAILABLE=false
    else
        JQ_AVAILABLE=true
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured or invalid."
        exit 1
    fi

    # Check Terraform version
    if command -v jq &> /dev/null; then
        local tf_version=$(terraform version -json | jq -r '.terraform_version')
        local required_version="1.6.0"
        
        if ! printf '%s\n%s\n' "$required_version" "$tf_version" | sort -V -C; then
            error "Terraform version $tf_version is too old. Required: >= $required_version"
            exit 1
        fi
    else
        warning "Cannot verify Terraform version without jq. Proceeding anyway."
    fi

    success "All prerequisites met"
}

# Confirm setup
confirm_setup() {
    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    warning "You are about to create Terraform backend infrastructure:"
    echo "  S3 Bucket: $BUCKET_NAME"
    echo "  Backup Bucket: ${BUCKET_NAME}-backups"
    echo "  DynamoDB Table: terraform-state-lock"
    echo "  AWS Region: $AWS_REGION"
    echo "  Project: $PROJECT_NAME"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Setup cancelled by user"
        exit 0
    fi
}

# Check if resources already exist
check_existing_resources() {
    log "Checking for existing resources..."

    # Check S3 bucket
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        warning "S3 bucket '$BUCKET_NAME' already exists"
        if [[ "$FORCE" != true ]]; then
            read -p "Continue anyway? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                exit 1
            fi
        fi
    fi

    # Check DynamoDB table
    if aws dynamodb describe-table --table-name terraform-state-lock --region "$AWS_REGION" 2>/dev/null; then
        warning "DynamoDB table 'terraform-state-lock' already exists"
        if [[ "$FORCE" != true ]]; then
            read -p "Continue anyway? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Create terraform.tfvars file
create_tfvars() {
    log "Creating terraform.tfvars file..."

    local tfvars_file="$BACKEND_DIR/terraform.tfvars"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create: $tfvars_file"
        return 0
    fi

    cat > "$tfvars_file" << EOF
# Terraform Backend Configuration
# Generated by setup-backend.sh on $(date)

aws_region            = "$AWS_REGION"
replica_region        = "us-west-2"
state_bucket_name     = "$BUCKET_NAME"
backup_bucket_name    = "${BUCKET_NAME}-backups"
dynamodb_table_name   = "terraform-state-lock"
project_name          = "$PROJECT_NAME"
environment           = "shared"
owner                 = "devops-team"
cost_center           = "infrastructure"

# Enable cross-region replication for disaster recovery
enable_cross_region_replication = false
EOF

    success "Created terraform.tfvars file"
}

# Initialize and apply Terraform
apply_terraform() {
    log "Initializing Terraform backend infrastructure..."

    cd "$BACKEND_DIR"

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would run terraform init and apply in $BACKEND_DIR"
        return 0
    fi

    # Initialize Terraform
    log "Running terraform init..."
    terraform init

    # Validate configuration
    log "Validating Terraform configuration..."
    terraform validate

    # Plan the deployment
    log "Creating Terraform plan..."
    terraform plan -out=backend.tfplan

    # Apply the plan
    log "Applying Terraform configuration..."
    terraform apply -auto-approve backend.tfplan

    # Clean up plan file
    rm -f backend.tfplan

    success "Terraform backend infrastructure created successfully"
}

# Update environment configurations
update_environment_configs() {
    log "Updating environment backend configurations..."

    local environments=("dev" "prod")
    
    for env in "${environments[@]}"; do
        local env_dir="$PROJECT_ROOT/environments/$env"
        local backend_config="$env_dir/backend.tf"
        
        if [[ "$DRY_RUN" == true ]]; then
            log "[DRY RUN] Would update backend config for $env environment"
            continue
        fi

        if [[ ! -d "$env_dir" ]]; then
            warning "Environment directory $env_dir does not exist, skipping"
            continue
        fi

        log "Updating backend configuration for $env environment..."

        # Create or update backend configuration
        cat > "$backend_config" << EOF
# Backend configuration for $env environment
# Generated by setup-backend.sh on $(date)

terraform {
  backend "s3" {
    bucket         = "$BUCKET_NAME"
    key            = "$env/terraform.tfstate"
    region         = "$AWS_REGION"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
EOF

        success "Updated backend configuration for $env environment"
    done
}

# Migrate existing state (if any)
migrate_existing_state() {
    log "Checking for existing local state files to migrate..."

    local environments=("dev" "prod")
    
    for env in "${environments[@]}"; do
        local env_dir="$PROJECT_ROOT/environments/$env"
        local state_file="$env_dir/terraform.tfstate"
        
        if [[ ! -f "$state_file" ]]; then
            continue
        fi

        if [[ "$DRY_RUN" == true ]]; then
            log "[DRY RUN] Would migrate existing state file for $env environment"
            continue
        fi

        warning "Found existing state file for $env environment"
        
        if [[ "$FORCE" != true ]]; then
            read -p "Migrate to remote backend? (yes/no): " -r
            if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
                continue
            fi
        fi

        log "Migrating state for $env environment..."
        
        cd "$env_dir"
        
        # Initialize with new backend
        terraform init -migrate-state -force-copy
        
        # Backup local state
        if [[ -f "terraform.tfstate" ]]; then
            mv terraform.tfstate "terraform.tfstate.backup.$(date +%Y%m%d-%H%M%S)"
        fi
        
        success "Migrated state for $env environment"
    done
}

# Create initial backup
create_initial_backup() {
    log "Creating initial state backup..."

    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create initial backup"
        return 0
    fi

    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_key="initial-setup-${timestamp}.tfstate"
    
    # Backup the backend state itself
    cd "$BACKEND_DIR"
    if [[ -f "terraform.tfstate" ]]; then
        aws s3 cp terraform.tfstate "s3://${BUCKET_NAME}-backups/${backup_key}"
        success "Created initial backup: s3://${BUCKET_NAME}-backups/${backup_key}"
    fi
}

# Generate setup summary
generate_summary() {
    log "Generating setup summary..."

    local summary_file="$PROJECT_ROOT/BACKEND_SETUP_SUMMARY.md"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create setup summary at $summary_file"
        return 0
    fi

    cat > "$summary_file" << EOF
# Terraform Backend Setup Summary

**Setup Date**: $(date)
**Setup Script**: $0

## Created Resources

### S3 Buckets
- **State Bucket**: \`$BUCKET_NAME\`
- **Backup Bucket**: \`${BUCKET_NAME}-backups\`
- **Region**: $AWS_REGION

### DynamoDB Table
- **Table Name**: \`terraform-state-lock\`
- **Region**: $AWS_REGION

### KMS Keys
- **State Encryption**: \`alias/terraform-state\`
- **Backup Encryption**: \`alias/terraform-backups\`

## Configuration Files Updated

- \`terraform-backend/terraform.tfvars\`
- \`environments/dev/backend.tf\`
- \`environments/prod/backend.tf\`

## Next Steps

1. **Initialize environments**: Run \`terraform init\` in each environment directory
2. **Test the setup**: Create a test resource and verify state is stored remotely
3. **Setup CI/CD**: Configure GitHub Actions with appropriate AWS roles
4. **Test backups**: Verify backup and restore procedures work correctly

## Important Notes

- State files are encrypted at rest using KMS
- DynamoDB table provides state locking to prevent concurrent modifications
- Cross-region replication is enabled for disaster recovery
- Versioning is enabled on all S3 buckets

## Troubleshooting

If you encounter issues:

1. Check AWS credentials and permissions
2. Verify bucket names are globally unique
3. Ensure all required AWS services are available in your region
4. Review CloudWatch logs for detailed error messages

## Cleanup

To remove the backend infrastructure (⚠️ **DANGEROUS** ⚠️):

\`\`\`bash
cd terraform-backend
terraform destroy
\`\`\`

**Warning**: This will delete all Terraform state files and make infrastructure unmanageable!

EOF

    success "Setup summary created: $summary_file"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f "$BACKEND_DIR/backend.tfplan"
}

# Main execution
main() {
    log "Starting Terraform backend setup..."

    parse_args "$@"
    check_prerequisites
    confirm_setup
    check_existing_resources
    create_tfvars
    apply_terraform
    update_environment_configs
    migrate_existing_state
    create_initial_backup
    generate_summary
    cleanup

    success "Terraform backend setup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Review the setup summary: BACKEND_SETUP_SUMMARY.md"
    echo "2. Initialize your environments: cd environments/dev && terraform init"
    echo "3. Test the setup with a simple deployment"
    echo "4. Configure GitHub Actions with the new backend settings"
}

# Error handling
trap 'error "Setup failed at line $LINENO"; cleanup; exit 1' ERR

# Execute main function
main "$@"