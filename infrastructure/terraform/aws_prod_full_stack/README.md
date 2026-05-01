# AWS Production Full Stack Terraform

This stack provisions a production-grade, three-tier AWS application platform with strong defaults for security, resilience, and observability.

## Provisioned Components

- VPC with 3-tier subnet layout across 2-3 Availability Zones
- Internet Gateway and one NAT Gateway per AZ
- Public ALB with HTTP->HTTPS redirect and TLS listener
- Optional WAFv2 web ACL with AWS managed rule groups
- Auto Scaling EC2 application tier with launch template hardening (IMDSv2, encrypted root volume)
- RDS PostgreSQL Multi-AZ instance with encryption, deletion protection, backups, and Performance Insights
- ElastiCache Redis replication group with Multi-AZ and encryption in transit/at rest
- KMS CMK for encryption domains
- S3 buckets for artifacts and ALB logs with versioning, encryption, and public access block
- CloudWatch log groups, VPC Flow Logs, and CloudWatch alarms
- SNS alert topic with optional email subscription
- IAM least-privilege instance profile baseline for app nodes

## Folder

- infrastructure/terraform/aws_prod_full_stack

## Usage

1. Copy terraform.tfvars.example to terraform.tfvars and set real values.
2. Export AWS credentials or use a CI role.
3. Run:

terraform init
terraform validate
terraform plan
terraform apply

## Important Inputs

- acm_certificate_arn: Required for HTTPS listener
- ami_id: Required for app launch template
- db_master_username: RDS admin user (password auto-managed by AWS Secrets Manager)
- redis_auth_token: Optional but recommended for Redis auth
- alarm_email_endpoint: Optional SNS email subscription

## Security Notes

- Do not commit secrets to source control.
- Use CI secret stores for sensitive tfvars values.
- Restrict allowed_ingress_cidrs to trusted edge ranges in production.
- ALB access-log bucket uses SSE-S3 for service compatibility; core data stores remain KMS encrypted.
- Consider adding organization-specific SCPs, Config Rules, GuardDuty, Security Hub, and centralized logging account integration.

## Operational Notes

- RDS deletion protection is enabled.
- ALB deletion protection is enabled.
- DB uses final snapshot on destroy.
- NAT Gateway is deployed per AZ for production availability.

## Suggested Next Enhancements

- Replace EC2 app tier with EKS or ECS if container-native runtime is required.
- Add Route53 record management for custom domains.
- Add AWS Backup plan and vault lock controls.
- Add CI policy checks with tfsec/checkov and OPA policy bundles.
