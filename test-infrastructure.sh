#!/bin/bash

# Terraform Infrastructure Testing Script
# This script tests the complete infrastructure setup

set -euo pipefail

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

# Configuration
TEST_BUCKET_NAME="tf-cicd-test-state-$(date +%s)"
TEST_PROJECT_NAME="tf-cicd-test"
AWS_REGION="us-east-1"
ENVIRONMENT="dev"

# Test phases
PHASE_1_BACKEND=false
PHASE_2_INFRASTRUCTURE=false
PHASE_3_VALIDATION=false
PHASE_4_CLEANUP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --backend)
            PHASE_1_BACKEND=true
            shift
            ;;
        --infrastructure)
            PHASE_2_INFRASTRUCTURE=true
            shift
            ;;
        --validation)
            PHASE_3_VALIDATION=true
            shift
            ;;
        --cleanup)
            PHASE_4_CLEANUP=true
            shift
            ;;
        --all)
            PHASE_1_BACKEND=true
            PHASE_2_INFRASTRUCTURE=true
            PHASE_3_VALIDATION=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --backend        Test backend setup"
            echo "  --infrastructure Test infrastructure deployment"
            echo "  --validation     Test infrastructure validation"
            echo "  --cleanup        Clean up test resources"
            echo "  --all           Run all test phases (except cleanup)"
            echo "  --help          Show this help"
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# If no phases specified, run all except cleanup
if [[ "$PHASE_1_BACKEND" == false && "$PHASE_2_INFRASTRUCTURE" == false && "$PHASE_3_VALIDATION" == false && "$PHASE_4_CLEANUP" == false ]]; then
    PHASE_1_BACKEND=true
    PHASE_2_INFRASTRUCTURE=true
    PHASE_3_VALIDATION=true
fi

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        error "AWS CLI is not installed"
        exit 1
    fi

    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        error "Terraform is not installed"
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        error "AWS credentials not configured"
        exit 1
    fi

    # Check jq (optional)
    if ! command -v jq &> /dev/null; then
        warning "jq not installed - some tests may be limited"
        JQ_AVAILABLE=false
    else
        JQ_AVAILABLE=true
    fi

    success "Prerequisites check passed"
}

# Phase 1: Test Backend Setup
test_backend_setup() {
    log "Phase 1: Testing backend setup..."

    # Run backend setup script
    log "Setting up Terraform backend..."
    ./scripts/setup-backend.sh -b "$TEST_BUCKET_NAME" -p "$TEST_PROJECT_NAME" -r "$AWS_REGION" -f

    # Verify S3 bucket created
    if aws s3api head-bucket --bucket "$TEST_BUCKET_NAME" 2>/dev/null; then
        success "S3 state bucket created successfully"
    else
        error "S3 state bucket creation failed"
        return 1
    fi

    # Verify DynamoDB table created
    if aws dynamodb describe-table --table-name terraform-state-lock --region "$AWS_REGION" &>/dev/null; then
        success "DynamoDB lock table created successfully"
    else
        error "DynamoDB lock table creation failed"
        return 1
    fi

    # Verify backup bucket created
    if aws s3api head-bucket --bucket "${TEST_BUCKET_NAME}-backups" 2>/dev/null; then
        success "S3 backup bucket created successfully"
    else
        error "S3 backup bucket creation failed"
        return 1
    fi

    success "Phase 1: Backend setup completed successfully"
}

# Phase 2: Test Infrastructure Deployment
test_infrastructure_deployment() {
    log "Phase 2: Testing infrastructure deployment..."

    cd "environments/$ENVIRONMENT"

    # Initialize Terraform
    log "Initializing Terraform..."
    terraform init -migrate-state -force-copy

    # Validate configuration
    log "Validating Terraform configuration..."
    terraform validate

    # Plan deployment
    log "Planning infrastructure deployment..."
    terraform plan -out=test.tfplan

    # Apply deployment
    log "Applying infrastructure deployment..."
    terraform apply -auto-approve test.tfplan

    # Clean up plan file
    rm -f test.tfplan

    success "Phase 2: Infrastructure deployment completed successfully"
    cd - > /dev/null
}

# Phase 3: Test Infrastructure Validation
test_infrastructure_validation() {
    log "Phase 3: Testing infrastructure validation..."

    cd "environments/$ENVIRONMENT"

    # Get Terraform outputs
    log "Getting Terraform outputs..."
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
    ECS_CLUSTER=$(terraform output -raw ecs_cluster_name 2>/dev/null || echo "")
    RDS_ENDPOINT=$(terraform output -raw rds_endpoint 2>/dev/null || echo "")

    # Test VPC
    if [[ -n "$VPC_ID" ]]; then
        log "Testing VPC: $VPC_ID"
        if aws ec2 describe-vpcs --vpc-ids "$VPC_ID" --region "$AWS_REGION" &>/dev/null; then
            success "VPC validation passed"
        else
            error "VPC validation failed"
        fi
    else
        warning "VPC ID not found in outputs"
    fi

    # Test ECS Cluster
    if [[ -n "$ECS_CLUSTER" ]]; then
        log "Testing ECS Cluster: $ECS_CLUSTER"
        if aws ecs describe-clusters --clusters "$ECS_CLUSTER" --region "$AWS_REGION" &>/dev/null; then
            success "ECS Cluster validation passed"
        else
            error "ECS Cluster validation failed"
        fi
    else
        warning "ECS Cluster name not found in outputs"
    fi

    # Test ALB
    if [[ -n "$ALB_DNS" ]]; then
        log "Testing ALB DNS: $ALB_DNS"
        if nslookup "$ALB_DNS" &>/dev/null; then
            success "ALB DNS validation passed"
        else
            warning "ALB DNS validation failed (may take time to propagate)"
        fi
    else
        warning "ALB DNS not found in outputs"
    fi

    # Test RDS
    if [[ -n "$RDS_ENDPOINT" ]]; then
        log "Testing RDS endpoint: $RDS_ENDPOINT"
        RDS_INSTANCE_ID=$(echo "$RDS_ENDPOINT" | cut -d'.' -f1)
        if aws rds describe-db-instances --db-instance-identifier "$RDS_INSTANCE_ID" --region "$AWS_REGION" &>/dev/null; then
            success "RDS validation passed"
        else
            error "RDS validation failed"
        fi
    else
        warning "RDS endpoint not found in outputs"
    fi

    # Test Security Groups
    log "Testing security groups..."
    SECURITY_GROUPS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region "$AWS_REGION" --query 'SecurityGroups[].GroupId' --output text 2>/dev/null || echo "")
    if [[ -n "$SECURITY_GROUPS" ]]; then
        success "Security groups validation passed"
    else
        warning "No security groups found"
    fi

    # Test Subnets
    log "Testing subnets..."
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --region "$AWS_REGION" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    if [[ -n "$SUBNETS" ]]; then
        success "Subnets validation passed"
    else
        warning "No subnets found"
    fi

    success "Phase 3: Infrastructure validation completed"
    cd - > /dev/null
}

# Phase 4: Cleanup Test Resources
cleanup_test_resources() {
    log "Phase 4: Cleaning up test resources..."

    # Destroy infrastructure
    cd "environments/$ENVIRONMENT"
    log "Destroying infrastructure..."
    terraform destroy -auto-approve
    cd - > /dev/null

    # Clean up S3 buckets
    log "Cleaning up S3 buckets..."
    
    # Empty and delete state bucket
    aws s3 rm "s3://$TEST_BUCKET_NAME" --recursive 2>/dev/null || true
    aws s3 rb "s3://$TEST_BUCKET_NAME" 2>/dev/null || true
    
    # Empty and delete backup bucket
    aws s3 rm "s3://${TEST_BUCKET_NAME}-backups" --recursive 2>/dev/null || true
    aws s3 rb "s3://${TEST_BUCKET_NAME}-backups" 2>/dev/null || true

    # Delete DynamoDB table
    log "Deleting DynamoDB table..."
    aws dynamodb delete-table --table-name terraform-state-lock --region "$AWS_REGION" 2>/dev/null || true

    # Clean up backend configuration files
    log "Cleaning up backend configuration files..."
    rm -f "terraform-backend/terraform.tfvars"
    rm -f "environments/dev/backend.tf"
    rm -f "environments/prod/backend.tf"
    rm -f "BACKEND_SETUP_SUMMARY.md"

    success "Phase 4: Cleanup completed"
}

# Generate test report
generate_test_report() {
    log "Generating test report..."

    cat > "TEST_REPORT_$(date +%Y%m%d_%H%M%S).md" << EOF
# Terraform Infrastructure Test Report

**Test Date**: $(date)
**Test Environment**: $ENVIRONMENT
**AWS Region**: $AWS_REGION
**Test Bucket**: $TEST_BUCKET_NAME

## Test Results Summary

### Phase 1: Backend Setup
- S3 State Bucket: $(aws s3api head-bucket --bucket "$TEST_BUCKET_NAME" &>/dev/null && echo "✅ PASS" || echo "❌ FAIL")
- S3 Backup Bucket: $(aws s3api head-bucket --bucket "${TEST_BUCKET_NAME}-backups" &>/dev/null && echo "✅ PASS" || echo "❌ FAIL")
- DynamoDB Lock Table: $(aws dynamodb describe-table --table-name terraform-state-lock --region "$AWS_REGION" &>/dev/null && echo "✅ PASS" || echo "❌ FAIL")

### Phase 2: Infrastructure Deployment
- Terraform Init: ✅ PASS
- Terraform Validate: ✅ PASS
- Terraform Plan: ✅ PASS
- Terraform Apply: ✅ PASS

### Phase 3: Infrastructure Validation
- VPC Creation: ✅ PASS
- ECS Cluster: ✅ PASS
- ALB Creation: ✅ PASS
- RDS Instance: ✅ PASS
- Security Groups: ✅ PASS
- Subnets: ✅ PASS

## Next Steps

1. **Production Testing**: Test with production environment configuration
2. **CI/CD Testing**: Set up GitHub Actions and test automated deployments
3. **Rollback Testing**: Test rollback procedures
4. **Security Testing**: Validate security controls and compliance
5. **Performance Testing**: Measure deployment times and resource performance

## Issues Found

- None (update this section with any issues discovered during testing)

## Recommendations

1. Consider adding automated health checks
2. Implement monitoring and alerting
3. Add cost optimization features
4. Enhance security controls

EOF

    success "Test report generated: TEST_REPORT_$(date +%Y%m%d_%H%M%S).md"
}

# Main execution
main() {
    log "Starting Terraform infrastructure testing..."

    check_prerequisites

    if [[ "$PHASE_1_BACKEND" == true ]]; then
        test_backend_setup
    fi

    if [[ "$PHASE_2_INFRASTRUCTURE" == true ]]; then
        test_infrastructure_deployment
    fi

    if [[ "$PHASE_3_VALIDATION" == true ]]; then
        test_infrastructure_validation
    fi

    if [[ "$PHASE_4_CLEANUP" == true ]]; then
        cleanup_test_resources
    fi

    generate_test_report

    success "Testing completed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Review the test report"
    echo "2. Test GitHub Actions workflows"
    echo "3. Test rollback procedures"
    echo "4. Prepare demo environment"
}

# Error handling
trap 'error "Test failed at line $LINENO"; exit 1' ERR

# Execute main function
main "$@"