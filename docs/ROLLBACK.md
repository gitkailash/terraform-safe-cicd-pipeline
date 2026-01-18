# Terraform Rollback Procedures

## Overview

This document provides comprehensive procedures for rolling back Terraform deployments when issues occur. The rollback strategy is designed to minimize downtime and ensure infrastructure stability.

## Rollback Decision Matrix

| Scenario | Recommended Method | Time to Execute | Risk Level |
|----------|-------------------|-----------------|------------|
| Configuration error | Git revert | 5-10 minutes | Low |
| Resource creation failure | Targeted destroy/recreate | 10-15 minutes | Medium |
| State corruption | State restore | 15-30 minutes | High |
| Complete deployment failure | Full rollback | 20-45 minutes | High |
| Security incident | Emergency procedures | Immediate | Critical |

## Prerequisites

Before performing any rollback:

1. **Assess the situation**
   - Identify the scope of the problem
   - Determine if rollback is necessary vs. forward fix
   - Check if any data loss could occur

2. **Notify stakeholders**
   - Alert the team via Slack #infrastructure-alerts
   - Create incident ticket
   - Inform management if production is affected

3. **Create backup**
   - Always backup current state before rollback
   - Document the current situation

## Rollback Methods

### Method 1: Git-Based Rollback (Recommended)

**When to use**: Configuration errors, failed deployments due to code issues

**Advantages**:
- Maintains full audit trail
- Easy to understand and review
- Can be automated
- Preserves infrastructure history

**Steps**:

1. **Identify the problematic commit**
   ```bash
   git log --oneline -10
   # Find the last known good commit
   ```

2. **Create rollback branch**
   ```bash
   git checkout -b rollback-prod-$(date +%Y%m%d-%H%M%S)
   ```

3. **Revert the problematic commit**
   ```bash
   git revert HEAD --no-edit
   # Or revert specific commit: git revert <commit-hash> --no-edit
   ```

4. **Test the rollback**
   ```bash
   cd environments/prod
   terraform init
   terraform plan -out=rollback.tfplan
   # Review the plan carefully
   ```

5. **Apply the rollback**
   ```bash
   terraform apply rollback.tfplan
   ```

6. **Verify the rollback**
   ```bash
   # Run health checks
   curl -f https://your-app.example.com/health
   
   # Check application logs
   aws logs tail /aws/ecs/myapp-prod --follow
   ```

### Method 2: State File Restoration

**When to use**: State corruption, accidental state modifications

**Advantages**:
- Quick recovery from state issues
- Preserves resource configurations
- Minimal infrastructure changes

**Steps**:

1. **List available backups**
   ```bash
   aws s3 ls s3://your-backup-bucket/ | grep prod | sort -k1,2
   ```

2. **Choose appropriate backup**
   ```bash
   # Select backup from before the issue occurred
   BACKUP_FILE="backup-prod-20240118-140000.tfstate"
   ```

3. **Create current state backup**
   ```bash
   aws s3 cp s3://your-terraform-state-bucket/prod/terraform.tfstate \
     s3://your-backup-bucket/pre-rollback-$(date +%Y%m%d-%H%M%S).tfstate
   ```

4. **Restore the backup**
   ```bash
   aws s3 cp s3://your-backup-bucket/$BACKUP_FILE \
     s3://your-terraform-state-bucket/prod/terraform.tfstate
   ```

5. **Refresh and validate**
   ```bash
   cd environments/prod
   terraform init
   terraform refresh
   terraform plan
   ```

### Method 3: Targeted Resource Rollback

**When to use**: Specific resource issues, partial deployment failures

**Advantages**:
- Minimal impact on other resources
- Faster than full rollback
- Surgical precision

**Steps**:

1. **Identify problematic resources**
   ```bash
   terraform state list | grep <resource_pattern>
   ```

2. **Backup current state**
   ```bash
   terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate
   ```

3. **Destroy problematic resources**
   ```bash
   terraform destroy -target=aws_instance.web -auto-approve
   ```

4. **Recreate from previous configuration**
   ```bash
   git checkout HEAD~1 -- environments/prod/main.tf
   terraform apply -target=aws_instance.web -auto-approve
   ```

### Method 4: Blue-Green Rollback

**When to use**: Zero-downtime rollbacks, critical production systems

**Advantages**:
- Zero downtime
- Easy to test before switching
- Quick rollback capability

**Steps**:

1. **Prepare green environment**
   ```bash
   cd environments/prod-green
   terraform init
   terraform apply
   ```

2. **Test green environment**
   ```bash
   # Run comprehensive tests
   ./scripts/health-check.sh prod-green
   ```

3. **Switch traffic to green**
   ```bash
   # Update DNS or load balancer configuration
   aws route53 change-resource-record-sets \
     --hosted-zone-id Z123456789 \
     --change-batch file://switch-to-green.json
   ```

4. **Monitor and validate**
   ```bash
   # Monitor application metrics
   # Check error rates and response times
   ```

## Automated Rollback Script Usage

The repository includes an automated rollback script at `scripts/rollback.sh`.

### Basic Usage

```bash
# Git-based rollback for production
./scripts/rollback.sh -e prod -m git

# State-based rollback with specific backup
./scripts/rollback.sh -e prod -m state -b backup-prod-20240118-140000.tfstate

# Targeted resource rollback
./scripts/rollback.sh -e prod -m destroy -t aws_instance.web

# Dry run to see what would happen
./scripts/rollback.sh -e prod -m git --dry-run
```

### Advanced Options

```bash
# Force rollback without confirmation
./scripts/rollback.sh -e prod -m git --force

# Rollback with custom target
./scripts/rollback.sh -e prod -m destroy -t module.ecs.aws_ecs_service.app

# Help and usage information
./scripts/rollback.sh --help
```

## Environment-Specific Considerations

### Development Environment

- **Approval**: No manual approval required
- **Backup**: Optional (can be skipped for speed)
- **Notification**: Slack notification only
- **Testing**: Basic health checks sufficient

```bash
# Quick dev rollback
./scripts/rollback.sh -e dev -m git --force
```

### Production Environment

- **Approval**: Manual approval required
- **Backup**: Mandatory before any changes
- **Notification**: Slack + PagerDuty + Email
- **Testing**: Comprehensive health checks required

```bash
# Production rollback with full safety checks
./scripts/rollback.sh -e prod -m git
```

## Health Checks and Validation

### Application Health Checks

```bash
# Basic health endpoint
curl -f https://your-app.example.com/health

# Detailed health with metrics
curl -s https://your-app.example.com/health | jq '.'

# Database connectivity
curl -f https://your-app.example.com/health/db
```

### Infrastructure Health Checks

```bash
# ECS service status
aws ecs describe-services \
  --cluster myapp-prod \
  --services myapp-prod-service

# Load balancer target health
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/myapp-prod/1234567890123456

# RDS instance status
aws rds describe-db-instances \
  --db-instance-identifier myapp-prod-db
```

### Performance Validation

```bash
# Response time check
curl -w "@curl-format.txt" -o /dev/null -s https://your-app.example.com/

# Load test (if appropriate)
ab -n 100 -c 10 https://your-app.example.com/
```

## Rollback Failure Recovery

If a rollback fails, follow these emergency procedures:

### 1. Stop All Operations
```bash
# Kill any running Terraform processes
pkill -f terraform

# Lock the state to prevent concurrent modifications
echo "EMERGENCY_LOCK" | aws s3 cp - s3://your-terraform-state-bucket/LOCK
```

### 2. Assess the Situation
```bash
# Check Terraform state
terraform show

# Check AWS resources directly
aws ec2 describe-instances --filters "Name=tag:Environment,Values=prod"
```

### 3. Manual Recovery
```bash
# Import resources that exist but aren't in state
terraform import aws_instance.web i-1234567890abcdef0

# Remove resources from state that don't exist
terraform state rm aws_instance.phantom
```

### 4. Emergency Contacts
- Escalate to senior DevOps engineer
- Contact AWS support if needed
- Inform management of the situation

## Post-Rollback Procedures

### Immediate Actions (0-30 minutes)

1. **Verify system stability**
   - Run comprehensive health checks
   - Monitor error rates and performance metrics
   - Check application logs for errors

2. **Document the incident**
   - Record timeline of events
   - Note what triggered the rollback
   - Document any data loss or service impact

3. **Communicate status**
   - Update incident ticket
   - Notify stakeholders of resolution
   - Post status update in team channels

### Short-term Actions (1-24 hours)

1. **Root cause analysis**
   - Investigate what caused the original failure
   - Review deployment process
   - Check for any underlying issues

2. **Fix the underlying issue**
   - Create fix for the original problem
   - Test fix in development environment
   - Plan proper deployment of fix

3. **Update procedures**
   - Document lessons learned
   - Update rollback procedures if needed
   - Improve monitoring and alerting

### Long-term Actions (1-7 days)

1. **Post-mortem meeting**
   - Conduct blameless post-mortem
   - Identify process improvements
   - Create action items for prevention

2. **Process improvements**
   - Enhance testing procedures
   - Improve deployment automation
   - Update documentation

## Rollback Testing

### Monthly Rollback Drills

1. **Schedule regular drills**
   - Test rollback procedures monthly
   - Rotate team members to ensure knowledge sharing
   - Document drill results and improvements

2. **Test scenarios**
   - Simulated deployment failures
   - State corruption scenarios
   - Network connectivity issues

### Automated Testing

```bash
# Test rollback script functionality
./scripts/test-rollback.sh

# Validate backup and restore procedures
./scripts/test-backup-restore.sh
```

## Monitoring and Alerting

### Rollback Metrics

- Time to detect issue
- Time to initiate rollback
- Time to complete rollback
- Success rate of rollbacks

### Alerts

- Failed rollback attempts
- Long-running rollback operations
- Health check failures post-rollback

## Common Issues and Solutions

### Issue: Terraform State Lock

**Symptoms**: "Error acquiring the state lock"

**Solution**:
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Or wait for lock to expire (usually 20 minutes)
```

### Issue: Resource Dependencies

**Symptoms**: "Resource has dependencies and cannot be destroyed"

**Solution**:
```bash
# Destroy in correct order
terraform destroy -target=aws_instance.web
terraform destroy -target=aws_security_group.web
```

### Issue: State Drift

**Symptoms**: Plan shows unexpected changes

**Solution**:
```bash
# Refresh state to match reality
terraform refresh

# Import missing resources
terraform import aws_instance.web i-1234567890abcdef0
```

---

**Document Version**: 1.0  
**Last Updated**: January 18, 2026  
**Next Review**: April 18, 2026  
**Owner**: DevOps Team