# 📖 Terraform CI/CD Pipeline - User Manual

## **Table of Contents**
1. [Quick Start](#quick-start)
2. [Daily Operations](#daily-operations)
3. [Deployment Procedures](#deployment-procedures)
4. [Rollback Procedures](#rollback-procedures)
5. [Monitoring & Troubleshooting](#monitoring--troubleshooting)
6. [Security & Compliance](#security--compliance)
7. [Cost Management](#cost-management)
8. [Advanced Operations](#advanced-operations)

---

## **🚀 Quick Start**

### **For New Team Members**

#### **Prerequisites**
- AWS CLI configured with appropriate permissions
- Terraform >= 1.6.0 installed
- Git access to the repository
- Basic understanding of AWS services

#### **First Time Setup**
```bash
# 1. Clone the repository
git clone <repository-url>
cd terraform-cicd-pipeline

# 2. Verify tools
aws sts get-caller-identity
terraform --version

# 3. Initialize development environment
cd environments/dev
terraform init

# 4. Check current state
terraform plan
```

#### **Understanding the Structure**
```
terraform-cicd-pipeline/
├── environments/          # Environment-specific configurations
│   ├── dev/              # Development environment
│   └── prod/             # Production environment
├── modules/              # Reusable Terraform modules
│   ├── vpc/              # VPC and networking
│   ├── alb/              # Application Load Balancer
│   ├── ecs/              # ECS container platform
│   └── rds/              # RDS database
├── scripts/              # Automation scripts
└── docs/                 # Documentation
```

---

## **⚙️ Daily Operations**

### **Checking Infrastructure Status**

#### **View Current Resources**
```bash
# Go to environment directory
cd environments/dev  # or prod

# Check what's deployed
terraform show

# Get output values
terraform output

# Check specific resource
terraform state show aws_instance.example
```

#### **Health Checks**
```bash
# Check ALB health
ALB_DNS=$(terraform output -raw alb_dns_name)
curl -I http://$ALB_DNS/health

# Check RDS connectivity
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
echo "RDS endpoint: $RDS_ENDPOINT"

# Check ECS cluster
ECS_CLUSTER=$(terraform output -raw ecs_cluster_name)
aws ecs describe-clusters --clusters $ECS_CLUSTER
```

### **Monitoring Resources**

#### **CloudWatch Logs**
```bash
# View application logs
aws logs tail /aws/ecs/tf-cicd-pipeline-dev --follow

# View specific log stream
aws logs describe-log-streams --log-group-name /aws/ecs/tf-cicd-pipeline-dev
```

#### **Resource Utilization**
```bash
# ECS service status
aws ecs describe-services --cluster tf-cicd-pipeline-dev --services your-service

# RDS performance
aws rds describe-db-instances --db-instance-identifier tf-cicd-pipeline-dev-db

# ALB target health
aws elbv2 describe-target-health --target-group-arn $(terraform output -raw target_group_arn)
```

---

## **🚀 Deployment Procedures**

### **Development Environment Deployment**

#### **Standard Deployment Process**
```bash
# 1. Navigate to dev environment
cd environments/dev

# 2. Pull latest changes
git pull origin main

# 3. Initialize (if needed)
terraform init

# 4. Plan changes
terraform plan -out=deployment.tfplan

# 5. Review plan carefully
# Look for unexpected changes or deletions

# 6. Apply changes
terraform apply deployment.tfplan

# 7. Verify deployment
terraform output
```

#### **Quick Deployment Commands**
```bash
# One-liner for small changes
terraform plan && terraform apply -auto-approve

# With backup
terraform state pull > backup-$(date +%Y%m%d-%H%M%S).tfstate
terraform apply -auto-approve
```

### **Production Environment Deployment**

#### **Production Deployment Checklist**
- [ ] Changes tested in development environment
- [ ] Code reviewed and approved
- [ ] Backup created
- [ ] Maintenance window scheduled (if required)
- [ ] Rollback plan prepared
- [ ] Team notified

#### **Production Deployment Process**
```bash
# 1. Create backup
cd environments/prod
terraform state pull > backup-prod-$(date +%Y%m%d-%H%M%S).tfstate

# 2. Plan deployment
terraform plan -out=prod-deployment.tfplan

# 3. Review plan with team
# Share plan output for review

# 4. Apply during maintenance window
terraform apply prod-deployment.tfplan

# 5. Verify deployment
./scripts/health-check.sh prod

# 6. Monitor for issues
# Watch logs and metrics for 30 minutes
```

### **Configuration Changes**

#### **Updating Variables**
```bash
# Edit variables file
vim environments/dev/terraform.tfvars

# Example changes:
desired_count = 3
instance_class = "db.t3.small"

# Apply changes
terraform plan
terraform apply
```

#### **Adding New Resources**
```bash
# Edit main.tf
vim environments/dev/main.tf

# Add new resource block
# Validate syntax
terraform validate

# Plan and apply
terraform plan
terraform apply
```

---

## **🔄 Rollback Procedures**

### **Automated Rollback**

#### **Using Rollback Script**
```bash
# Quick rollback to previous state
./scripts/rollback.sh -e dev -m git

# Rollback with specific backup
./scripts/rollback.sh -e dev -m state -b backup-20240127-140000.tfstate

# Dry run to see what would happen
./scripts/rollback.sh -e dev -m git --dry-run
```

#### **Rollback Options**
- **Git-based**: Revert code changes and re-apply
- **State-based**: Restore previous state file
- **Targeted**: Rollback specific resources only
- **Blue-green**: Switch traffic to previous environment

### **Manual Rollback**

#### **Git-Based Rollback**
```bash
# 1. Find last working commit
git log --oneline -10

# 2. Revert to previous commit
git revert HEAD --no-edit

# 3. Apply reverted configuration
terraform plan
terraform apply
```

#### **State-Based Rollback**
```bash
# 1. List available backups
aws s3 ls s3://your-backup-bucket/ | grep dev

# 2. Download backup
aws s3 cp s3://your-backup-bucket/backup-dev-20240127.tfstate ./restore.tfstate

# 3. Replace current state
terraform state push restore.tfstate

# 4. Refresh and verify
terraform refresh
terraform plan
```

#### **Targeted Rollback**
```bash
# Rollback specific resource
terraform destroy -target=aws_instance.problematic
terraform apply -target=aws_instance.problematic

# Import existing resource
terraform import aws_instance.existing i-1234567890abcdef0
```

### **Emergency Procedures**

#### **Complete Environment Rebuild**
```bash
# 1. Backup current state
terraform state pull > emergency-backup-$(date +%Y%m%d-%H%M%S).tfstate

# 2. Destroy everything
terraform destroy -auto-approve

# 3. Rebuild from scratch
terraform apply -auto-approve

# 4. Restore data from backups (if needed)
```

#### **Partial Service Recovery**
```bash
# Recover specific services
terraform apply -target=module.ecs
terraform apply -target=module.rds
terraform apply -target=module.alb
```

---

## **📊 Monitoring & Troubleshooting**

### **Health Monitoring**

#### **Application Health Checks**
```bash
# ALB health check
curl -f http://$(terraform output -raw alb_dns_name)/health

# Database connectivity
psql -h $(terraform output -raw rds_endpoint) -U dbadmin -d myapp_dev -c "SELECT 1;"

# ECS service health
aws ecs describe-services --cluster $(terraform output -raw ecs_cluster_name) --services your-service
```

#### **Infrastructure Monitoring**
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ClusterName,Value=$(terraform output -raw ecs_cluster_name) \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

### **Common Issues & Solutions**

#### **Terraform State Lock**
```bash
# Problem: "Error acquiring the state lock"
# Solution:
terraform force-unlock <lock-id>

# Prevention: Always use proper workflow
```

#### **Resource Conflicts**
```bash
# Problem: "Resource already exists"
# Solution: Import existing resource
terraform import aws_vpc.main vpc-12345678

# Or: Remove from state if not needed
terraform state rm aws_vpc.old
```

#### **Permission Errors**
```bash
# Problem: "Access Denied"
# Check AWS credentials
aws sts get-caller-identity

# Check IAM permissions
aws iam simulate-principal-policy \
  --policy-source-arn $(aws sts get-caller-identity --query Arn --output text) \
  --action-names ec2:DescribeVpcs \
  --resource-arns "*"
```

#### **Network Connectivity Issues**
```bash
# Check security groups
aws ec2 describe-security-groups --group-ids $(terraform output -raw alb_security_group_id)

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)"

# Check NAT gateways
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$(terraform output -raw vpc_id)"
```

### **Log Analysis**

#### **Application Logs**
```bash
# Stream live logs
aws logs tail /aws/ecs/tf-cicd-pipeline-dev --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/ecs/tf-cicd-pipeline-dev \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000
```

#### **Infrastructure Logs**
```bash
# CloudTrail events
aws logs filter-log-events \
  --log-group-name CloudTrail/ManagementEvents \
  --filter-pattern "{ $.eventName = CreateVpc || $.eventName = DeleteVpc }" \
  --start-time $(date -d '1 hour ago' +%s)000
```

---

## **🔒 Security & Compliance**

### **Security Best Practices**

#### **Access Control**
```bash
# Check IAM roles
aws iam list-roles --query 'Roles[?contains(RoleName, `terraform`)]'

# Review security groups
aws ec2 describe-security-groups --query 'SecurityGroups[?VpcId==`$(terraform output -raw vpc_id)`]'

# Check S3 bucket policies
aws s3api get-bucket-policy --bucket $(terraform output -raw assets_bucket_name)
```

#### **Encryption Verification**
```bash
# Check RDS encryption
aws rds describe-db-instances --db-instance-identifier $(terraform output -raw rds_instance_id) \
  --query 'DBInstances[0].StorageEncrypted'

# Check S3 encryption
aws s3api get-bucket-encryption --bucket $(terraform output -raw assets_bucket_name)

# Check EBS encryption
aws ec2 describe-volumes --filters "Name=tag:Environment,Values=dev" \
  --query 'Volumes[*].Encrypted'
```

### **Compliance Checks**

#### **Audit Trail**
```bash
# Check CloudTrail logs
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=CreateVpc \
  --start-time $(date -d '24 hours ago' +%Y-%m-%d) \
  --end-time $(date +%Y-%m-%d)

# Review Terraform state changes
git log --oneline --since="1 week ago" -- environments/
```

#### **Security Scanning**
```bash
# Check for public resources
aws ec2 describe-instances --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'Reservations[*].Instances[?PublicIpAddress!=null]'

# Check security group rules
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$(terraform output -raw vpc_id)" \
  --query 'SecurityGroups[?IpPermissions[?IpRanges[?CidrIp==`0.0.0.0/0`]]]'
```

---

## **💰 Cost Management**

### **Cost Monitoring**

#### **Resource Costs**
```bash
# Get cost by service
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '1 month ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE

# Get cost by resource
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '1 week ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=RESOURCE_ID
```

#### **Cost Optimization**
```bash
# Check unused resources
aws ec2 describe-instances --filters "Name=instance-state-name,Values=stopped"

# Check unattached EBS volumes
aws ec2 describe-volumes --filters "Name=status,Values=available"

# Check unused Elastic IPs
aws ec2 describe-addresses --query 'Addresses[?AssociationId==null]'
```

### **Auto-Shutdown Configuration**

#### **Enable Auto-Shutdown**
```bash
# Update variables
echo 'enable_auto_shutdown = true' >> environments/dev/terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

#### **Manual Shutdown**
```bash
# Shutdown development environment
aws lambda invoke \
  --function-name $(terraform output -raw auto_shutdown_function_name) \
  --payload '{"environment":"dev","action":"shutdown"}' \
  response.json

# Startup development environment
aws lambda invoke \
  --function-name $(terraform output -raw auto_shutdown_function_name) \
  --payload '{"environment":"dev","action":"startup"}' \
  response.json
```

---

## **🔧 Advanced Operations**

### **State Management**

#### **State Inspection**
```bash
# List all resources in state
terraform state list

# Show specific resource
terraform state show aws_vpc.main

# Move resource in state
terraform state mv aws_instance.old aws_instance.new

# Remove resource from state
terraform state rm aws_instance.unused
```

#### **State Backup and Recovery**
```bash
# Create manual backup
terraform state pull > manual-backup-$(date +%Y%m%d-%H%M%S).tfstate

# Restore from backup
terraform state push backup-file.tfstate

# Compare states
diff <(terraform state pull) backup-file.tfstate
```

### **Module Development**

#### **Testing Module Changes**
```bash
# Test module locally
cd modules/vpc
terraform init
terraform validate

# Test with example
terraform plan -var-file=../../environments/dev/terraform.tfvars
```

#### **Module Versioning**
```bash
# Tag module versions
git tag -a v1.0.0 -m "VPC module v1.0.0"
git push origin v1.0.0

# Use specific version
module "vpc" {
  source = "git::https://github.com/your-org/terraform-modules.git//vpc?ref=v1.0.0"
  # ...
}
```

### **Multi-Environment Management**

#### **Environment Promotion**
```bash
# Promote dev config to staging
cp environments/dev/main.tf environments/staging/
# Edit staging-specific values

# Promote staging to prod
cp environments/staging/main.tf environments/prod/
# Edit production-specific values
```

#### **Environment Comparison**
```bash
# Compare configurations
diff environments/dev/main.tf environments/prod/main.tf

# Compare states
terraform state pull > dev-state.json
cd ../prod
terraform state pull > prod-state.json
diff ../dev/dev-state.json prod-state.json
```

---

## **📞 Support & Escalation**

### **Getting Help**

#### **Internal Support**
1. **Check Documentation**: Review this manual and project README
2. **Search Logs**: Check CloudWatch and Terraform logs
3. **Team Chat**: Ask in #infrastructure-team channel
4. **Create Ticket**: Use internal ticketing system

#### **External Support**
1. **AWS Support**: For AWS service issues
2. **Terraform Community**: For Terraform-specific problems
3. **Vendor Support**: For third-party tool issues

### **Escalation Process**

#### **Severity Levels**
- **P1 (Critical)**: Production down, data loss risk
- **P2 (High)**: Major functionality impacted
- **P3 (Medium)**: Minor functionality impacted
- **P4 (Low)**: Enhancement requests, questions

#### **Escalation Contacts**
- **P1/P2**: Immediate escalation to on-call engineer
- **P3**: Team lead within 4 hours
- **P4**: Regular team channels

---

## **📚 Additional Resources**

### **Documentation Links**
- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/)
- [Project README](README.md)
- [Deployment Guide](DEPLOYMENT.md)
- [Rollback Procedures](ROLLBACK.md)

### **Training Materials**
- Terraform fundamentals course
- AWS architecture training
- Infrastructure as Code best practices
- Security and compliance training

### **Tools & Utilities**
- [Terraform Visual](https://github.com/hieven/terraform-visual) - Visualize Terraform plans
- [Terragrunt](https://terragrunt.gruntwork.io/) - Terraform wrapper
- [Checkov](https://www.checkov.io/) - Security scanning
- [TFLint](https://github.com/terraform-linters/tflint) - Terraform linting

---

## **🎯 Quick Reference**

### **Common Commands**
```bash
# Initialize
terraform init

# Plan changes
terraform plan

# Apply changes
terraform apply

# Show current state
terraform show

# Get outputs
terraform output

# Validate config
terraform validate

# Format code
terraform fmt

# Destroy resources
terraform destroy
```

### **Emergency Contacts**
- **Infrastructure Team**: #infrastructure-alerts
- **On-Call Engineer**: +1-555-ONCALL
- **AWS Support**: +1-206-266-4064
- **Management**: escalation@company.com

### **Important URLs**
- **AWS Console**: https://console.aws.amazon.com
- **Terraform Cloud**: https://app.terraform.io
- **Monitoring Dashboard**: https://monitoring.company.com
- **Documentation**: https://docs.company.com

---

**Remember**: When in doubt, ask for help. It's better to ask questions than to cause an outage. This infrastructure is critical to the business, and we're all here to support each other in maintaining it reliably and securely.