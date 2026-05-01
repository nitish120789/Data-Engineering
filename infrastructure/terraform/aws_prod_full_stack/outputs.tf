output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for az in local.azs : aws_subnet.public[az].id]
}

output "app_subnet_ids" {
  description = "Application subnet IDs"
  value       = [for az in local.azs : aws_subnet.app[az].id]
}

output "data_subnet_ids" {
  description = "Data subnet IDs"
  value       = [for az in local.azs : aws_subnet.data[az].id]
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.app.dns_name
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = aws_autoscaling_group.app.name
}

output "rds_endpoint" {
  description = "RDS endpoint"
  value       = aws_db_instance.app.address
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN that stores generated RDS master password"
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
}

output "redis_primary_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.app.primary_endpoint_address
}

output "sns_alert_topic_arn" {
  description = "SNS topic ARN for infrastructure alerts"
  value       = aws_sns_topic.alerts.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = aws_kms_key.app.arn
}

output "artifacts_bucket" {
  description = "S3 bucket for artifacts"
  value       = aws_s3_bucket.artifacts.id
}
