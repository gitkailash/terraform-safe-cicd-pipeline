# Disaster Recovery Runbook

## Overview

This document provides step-by-step procedures for recovering from various disaster scenarios that could affect our Terraform-managed infrastructure. Each scenario includes impact assessment, immediate response steps, and detailed recovery procedures.

## Emergency Contacts

| Role | Contact | Phone | Email |
|------|---------|-------|-------|
| DevOps Lead | John Doe | +1-555-0101 | john.doe@company.com |
| Infrastructure Team | On-Call | +1-555-0911 | devops-oncall@company.com |
| Security Team | Security SOC | +1-555-0999 | security@company.com |
| Management | CTO | +1-555-0001 | cto@company.com |

**Emergency Escalation**: PagerDuty → Slack #infrastructure-alerts → Phone calls

## Disaster Scenarios

### Scenario 1: Corrupted Terraform State File

**Impact**: Unable to manage infrastructure, potential for resource drift and conflicts

**Symptoms**:
- Terraform commands fail with state-related errors
- State file appears corrupted or missing
- Resources exist in AWS but not in state

**Immediate Response** (0-15 minutes):
1. **STOP** all Terraform operations immediately
2. Alert the team via Slack #infrastructure-alerts
3. Create incident in PagerDuty
4. Document current time and symptoms

**Recovery Steps**:

#### Step 1: Assess the Damage
```bash
# Check if state file exists
aws s3 ls s3://your-terraform-state-bucket/prod/terraform.tfstate

# Check state file versions
aws s3api list-object-versions \
  --bucket your-terraform-state-bucket \
  --prefix prod/terraform.tfstate

# Download current state for analysis
aws s3 cp s3://your-terraform-state-bucket/prod/terraform.tfstate ./current-state.tfstate
```

#### Step 2: Restore from Backup
```bash
# List available backups
aws s3 ls s3://your-backup-bucket/ | grep prod

# Restore from most recent backup
BACKUP_FILE="backup-prod-20240118-120000.tfstate"
aws s3 cp s3://your-backup-bucket/$BACKUP_FILE \
  s3://your-terraform-state-bucket/prod/terraform.tfstate

# Verify restoration
terraform init
terraform plan
```

#### Step 3: Reconcile State with Reality
```bash
# Import any missing resources
terraform import aws_instance.web i-1234567890abcdef0

# Remove any phantom resources
terraform state rm aws_instance.phantom

# Refresh state to match current infrastructure
terraform refresh
```

#### Step 4: Validate Recovery
```bash
# Run a plan to ensure state is consistent
terraform plan

# Verify critical resources are accessible
curl -f https://your-app.example.com/health
```

**Prevention**:
- Automated daily state backups
- State file versioning enabled
- Cross-region replication of state bucket

---

### Scenario 2: Failed Production Deployment with Service Outage

**Impact**: Production services unavailable, potential data loss, customer impact

**Symptoms**:
- Application health checks failing
- 5xx errors from load balancer
- Database connectivity issues
- Monitoring alerts firing

**Immediate Response** (0-5 minutes):
1. **ACTIVATE** incident response team
2. **ASSESS** scope of outage using monitoring dashboards
3. **COMMUNICATE** with stakeholders
4. **DECIDE** on rollback vs. forward fix

**Recovery Steps**:

#### Option A: Automated Rollback (Preferred)
```bash
# Trigger automated rollback
./scripts/rollback.sh -e prod -m git -f

# Monitor rollback progress
watch -n 5 'curl -s https://your-app.example.com/health'
```

#### Option B: Manual Rollback
```bash
# Revert to previous Git commit
git log --oneline -10  # Find last working commit
git revert HEAD --no-edit

# Apply reverted configuration
cd environments/prod
terraform plan -out=rollback.tfplan
terraform apply rollback.tfplan
```

#### Option C: Infrastructure Restore
```bash
# Restore from pre-deployment backup
BACKUP_ID="pre-deployment-20240118-140000.tfstate"
./scripts/rollback.sh -e prod -m state -b $BACKUP_ID -f
```

**Post-Recovery Actions**:
1. Verify all services are operational
2. Check data integrity
3. Review logs for root cause
4. Update incident timeline
5. Schedule post-mortem meeting

---

### Scenario 3: AWS Account Compromise

**Impact**: Potential unauthorized infrastructure changes, security breach, data exposure

**Symptoms**:
- Unexpected AWS resource changes
- Unusual API calls in CloudTrail
- Security alerts from AWS
- Terraform state shows unknown modifications

**Immediate Response** (0-10 minutes):
1. **ISOLATE** compromised account
2. **ROTATE** all AWS credentials immediately
3. **ENABLE** CloudTrail logging if not already active
4. **CONTACT** AWS Support for assistance

**Recovery Steps**:

#### Step 1: Secure the Environment
```bash
# Disable compromised IAM users/roles
aws iam put-user-policy --user-name CompromisedUser \
  --policy-name DenyAll \
  --policy-document file://deny-all-policy.json

# Rotate GitHub Actions OIDC role
# Update AWS_ROLE_ARN_PROD secret in GitHub
```

#### Step 2: Assess Infrastructure Changes
```bash
# Check CloudTrail for unauthorized changes
aws logs filter-log-events \
  --log-group-name CloudTrail/ManagementEvents \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern '{ $.eventName = "CreateInstance" || $.eventName = "TerminateInstance" }'

# Compare current state with known good backup
terraform plan -detailed-exitcode
```

#### Step 3: Restore Clean State
```bash
# Restore from backup taken before compromise
CLEAN_BACKUP="backup-prod-20240118-100000.tfstate"
./scripts/rollback.sh -e prod -m state -b $CLEAN_BACKUP -f

# Remove any unauthorized resources
terraform destroy -target=aws_instance.unauthorized
```

#### Step 4: Harden Security
```bash
# Enable additional monitoring
aws cloudtrail create-trail --name SecurityAuditTrail \
  --s3-bucket-name security-audit-logs

# Update security groups to remove unauthorized access
terraform apply -target=aws_security_group.web
```

---

### Scenario 4: Complete AWS Region Failure

**Impact**: All infrastructure in primary region unavailable

**Symptoms**:
- AWS console inaccessible for the region
- All services in region returning errors
- DNS resolution failing for region-specific resources

**Recovery Steps**:

#### Step 1: Activate DR Region
```bash
# Switch to disaster recovery region
export AWS_DEFAULT_REGION=us-west-2

# Initialize Terraform in DR environment
cd environments/prod-dr
terraform init
terraform plan
terraform apply
```

#### Step 2: Update DNS Records
```bash
# Point DNS to DR region
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123456789 \
  --change-batch file://dns-failover.json
```

#### Step 3: Restore Data
```bash
# Restore database from cross-region backup
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier myapp-prod-dr \
  --db-snapshot-identifier myapp-prod-snapshot-latest
```

---

## Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Scenario | RTO | RPO | Priority |
|----------|-----|-----|----------|
| State File Corruption | 30 minutes | 1 hour | High |
| Failed Deployment | 15 minutes | 0 minutes | Critical |
| Account Compromise | 2 hours | 1 hour | Critical |
| Region Failure | 4 hours | 1 hour | Medium |

## Testing and Validation

### Monthly DR Tests
- Restore state file from backup
- Execute rollback procedures
- Validate monitoring and alerting
- Test communication procedures

### Quarterly Full DR Tests
- Complete region failover
- End-to-end application testing
- Data integrity validation
- Performance benchmarking

## Post-Incident Procedures

### Immediate (0-24 hours)
1. Ensure all systems are stable
2. Document timeline of events
3. Preserve logs and evidence
4. Communicate resolution to stakeholders

### Short-term (1-7 days)
1. Conduct post-mortem meeting
2. Identify root cause
3. Create action items for prevention
4. Update runbooks and procedures

### Long-term (1-4 weeks)
1. Implement preventive measures
2. Update monitoring and alerting
3. Conduct training sessions
4. Review and update DR procedures

## Useful Commands and Scripts

### State Management
```bash
# Backup current state
aws s3 cp s3://your-terraform-state-bucket/prod/terraform.tfstate \
  s3://your-backup-bucket/manual-backup-$(date +%Y%m%d-%H%M%S).tfstate

# List state resources
terraform state list

# Show specific resource
terraform state show aws_instance.web

# Remove resource from state
terraform state rm aws_instance.old
```

### Emergency Access
```bash
# Assume emergency break-glass role
aws sts assume-role \
  --role-arn arn:aws:iam::123456789012:role/EmergencyAccess \
  --role-session-name emergency-$(date +%s)

# Create temporary admin user
aws iam create-user --user-name emergency-admin-$(date +%s)
aws iam attach-user-policy --user-name emergency-admin-$(date +%s) \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

### Health Checks
```bash
# Application health
curl -f https://your-app.example.com/health

# Database connectivity
psql -h your-db.cluster-xyz.us-east-1.rds.amazonaws.com -U dbuser -d myapp -c "SELECT 1;"

# Load balancer status
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:...
```

## Contact Information for Vendors

| Vendor | Support Contact | Account ID | Priority |
|--------|----------------|------------|----------|
| AWS | +1-206-266-4064 | 123456789012 | Enterprise |
| GitHub | support@github.com | your-org | Team |
| PagerDuty | support@pagerduty.com | your-account | Professional |

---

**Document Version**: 1.0  
**Last Updated**: January 18, 2026  
**Next Review**: April 18, 2026  
**Owner**: DevOps Team