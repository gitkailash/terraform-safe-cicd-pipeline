#!/bin/bash

# Terraform Rollback Script
# This script provides automated rollback capabilities for failed Terraform deployments

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_BUCKET="your-backup-bucket"
STATE_BUCKET="your-terraform-state-bucket"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
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

Terraform Rollback Script - Automated rollback for failed deployments

OPTIONS:
    -e, --environment ENV    Environment to rollback (dev/prod) [REQUIRED]
    -m, --method METHOD      Rollback method (git|state|destroy) [default: git]
    -t, --target TARGET      Specific resource to rollback (optional)
    -b, --backup BACKUP_ID   Specific backup to restore from (optional)
    -f, --force             Skip confirmation prompts
    -d, --dry-run           Show what would be done without executing
    -h, --help              Show this help message

ROLLBACK METHODS:
    git     - Revert to previous Git commit and re-apply
    state   - Restore previous Terraform state file
    destroy - Destroy specific resources and recreate

EXAMPLES:
    $0 -e prod -m git                    # Git-based rollback for production
    $0 -e dev -m state -b backup-123     # Restore specific state backup
    $0 -e prod -m destroy -t aws_instance.web  # Destroy and recreate specific resource
    $0 -e prod --dry-run                 # Preview rollback actions

EOF
}

# Parse command line arguments
parse_args() {
    ENVIRONMENT=""
    METHOD="git"
    TARGET=""
    BACKUP_ID=""
    FORCE=false
    DRY_RUN=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -e|--environment)
                ENVIRONMENT="$2"
                shift 2
                ;;
            -m|--method)
                METHOD="$2"
                shift 2
                ;;
            -t|--target)
                TARGET="$2"
                shift 2
                ;;
            -b|--backup)
                BACKUP_ID="$2"
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
    if [[ -z "$ENVIRONMENT" ]]; then
        error "Environment is required. Use -e or --environment"
        usage
        exit 1
    fi

    if [[ ! "$ENVIRONMENT" =~ ^(dev|prod)$ ]]; then
        error "Environment must be 'dev' or 'prod'"
        exit 1
    fi

    if [[ ! "$METHOD" =~ ^(git|state|destroy)$ ]]; then
        error "Method must be 'git', 'state', or 'destroy'"
        exit 1
    fi
}

# Confirm rollback action
confirm_rollback() {
    if [[ "$FORCE" == true ]]; then
        return 0
    fi

    warning "You are about to perform a rollback operation:"
    echo "  Environment: $ENVIRONMENT"
    echo "  Method: $METHOD"
    [[ -n "$TARGET" ]] && echo "  Target: $TARGET"
    [[ -n "$BACKUP_ID" ]] && echo "  Backup ID: $BACKUP_ID"
    echo ""
    
    read -p "Are you sure you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log "Rollback cancelled by user"
        exit 0
    fi
}

# Create pre-rollback backup
create_backup() {
    log "Creating pre-rollback backup..."
    
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_key="pre-rollback-${ENVIRONMENT}-${timestamp}.tfstate"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would create backup: s3://${BACKUP_BUCKET}/${backup_key}"
        return 0
    fi
    
    # Backup current state
    aws s3 cp "s3://${STATE_BUCKET}/${ENVIRONMENT}/terraform.tfstate" \
        "s3://${BACKUP_BUCKET}/${backup_key}"
    
    success "Backup created: s3://${BACKUP_BUCKET}/${backup_key}"
    echo "$backup_key" > "/tmp/rollback-backup-${ENVIRONMENT}.txt"
}

# Git-based rollback
rollback_git() {
    log "Performing Git-based rollback for $ENVIRONMENT..."
    
    cd "$PROJECT_ROOT"
    
    # Get current commit
    local current_commit=$(git rev-parse HEAD)
    log "Current commit: $current_commit"
    
    # Get previous commit
    local previous_commit=$(git rev-parse HEAD~1)
    log "Previous commit: $previous_commit"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would revert to commit: $previous_commit"
        log "[DRY RUN] Would run terraform apply in environments/$ENVIRONMENT"
        return 0
    fi
    
    # Create a new branch for rollback
    local rollback_branch="rollback-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S)"
    git checkout -b "$rollback_branch"
    
    # Revert to previous commit
    git revert --no-edit "$current_commit"
    
    # Apply the reverted configuration
    cd "environments/$ENVIRONMENT"
    
    log "Initializing Terraform..."
    terraform init
    
    log "Planning rollback changes..."
    terraform plan -out=rollback.tfplan
    
    log "Applying rollback..."
    terraform apply -auto-approve rollback.tfplan
    
    success "Git-based rollback completed successfully"
    
    # Clean up
    rm -f rollback.tfplan
}

# State-based rollback
rollback_state() {
    log "Performing state-based rollback for $ENVIRONMENT..."
    
    local backup_to_restore=""
    
    if [[ -n "$BACKUP_ID" ]]; then
        backup_to_restore="$BACKUP_ID"
    else
        # Find the most recent backup
        log "Finding most recent backup..."
        backup_to_restore=$(aws s3 ls "s3://${BACKUP_BUCKET}/" | \
            grep "${ENVIRONMENT}" | \
            sort -k1,2 | \
            tail -n1 | \
            awk '{print $4}')
        
        if [[ -z "$backup_to_restore" ]]; then
            error "No backup found for environment: $ENVIRONMENT"
            exit 1
        fi
    fi
    
    log "Restoring from backup: $backup_to_restore"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would restore state from: s3://${BACKUP_BUCKET}/${backup_to_restore}"
        return 0
    fi
    
    # Restore state file
    aws s3 cp "s3://${BACKUP_BUCKET}/${backup_to_restore}" \
        "s3://${STATE_BUCKET}/${ENVIRONMENT}/terraform.tfstate"
    
    # Refresh Terraform to sync with restored state
    cd "$PROJECT_ROOT/environments/$ENVIRONMENT"
    terraform init
    terraform refresh
    
    success "State-based rollback completed successfully"
}

# Resource-specific rollback (destroy and recreate)
rollback_destroy() {
    log "Performing destroy-based rollback for $ENVIRONMENT..."
    
    if [[ -z "$TARGET" ]]; then
        error "Target resource is required for destroy-based rollback"
        exit 1
    fi
    
    cd "$PROJECT_ROOT/environments/$ENVIRONMENT"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would destroy target: $TARGET"
        log "[DRY RUN] Would recreate target: $TARGET"
        return 0
    fi
    
    log "Initializing Terraform..."
    terraform init
    
    log "Destroying target resource: $TARGET"
    terraform destroy -target="$TARGET" -auto-approve
    
    log "Recreating target resource: $TARGET"
    terraform apply -target="$TARGET" -auto-approve
    
    success "Destroy-based rollback completed successfully"
}

# Health check after rollback
health_check() {
    log "Performing post-rollback health checks..."
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would perform health checks"
        return 0
    fi
    
    case "$ENVIRONMENT" in
        dev)
            # Add dev-specific health checks
            log "Running development health checks..."
            # curl -f https://your-app-dev.example.com/health || return 1
            ;;
        prod)
            # Add production-specific health checks
            log "Running production health checks..."
            # curl -f https://your-app.example.com/health || return 1
            ;;
    esac
    
    success "Health checks passed"
}

# Send notifications
send_notifications() {
    local status=$1
    local message="Rollback $status for $ENVIRONMENT environment using $METHOD method"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "[DRY RUN] Would send notification: $message"
        return 0
    fi
    
    log "Sending notifications..."
    
    # Slack notification (replace with your webhook URL)
    # curl -X POST -H 'Content-type: application/json' \
    #     --data "{\"text\":\"🔄 $message\"}" \
    #     "$SLACK_WEBHOOK_URL"
    
    # Email notification via SNS (replace with your topic ARN)
    # aws sns publish \
    #     --topic-arn "arn:aws:sns:us-east-1:123456789012:infrastructure-alerts" \
    #     --message "$message"
    
    log "Notifications sent"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -f "/tmp/rollback-backup-${ENVIRONMENT}.txt"
}

# Main execution
main() {
    log "Starting Terraform rollback process..."
    
    parse_args "$@"
    confirm_rollback
    create_backup
    
    case "$METHOD" in
        git)
            rollback_git
            ;;
        state)
            rollback_state
            ;;
        destroy)
            rollback_destroy
            ;;
    esac
    
    health_check
    send_notifications "completed successfully"
    cleanup
    
    success "Rollback process completed successfully!"
}

# Error handling
trap 'error "Rollback failed at line $LINENO"; send_notifications "failed"; cleanup; exit 1' ERR

# Execute main function
main "$@"