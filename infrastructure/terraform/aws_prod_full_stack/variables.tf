variable "aws_region" {
  description = "AWS region for deployment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project/application name used for resource naming."
  type        = string
  default     = "prod-app"
}

variable "environment" {
  description = "Environment label (prod, preprod, etc.)."
  type        = string
  default     = "prod"
}

variable "common_tags" {
  description = "Additional common tags applied to all resources."
  type        = map(string)
  default     = {}
}

variable "az_count" {
  description = "Number of AZs to use. Minimum 2, recommended 3 for production."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "allowed_ingress_cidrs" {
  description = "CIDRs allowed to reach public ALB listeners."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_waf" {
  description = "Whether to enable WAFv2 web ACL and attach to ALB."
  type        = bool
  default     = true
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for ALB HTTPS listener."
  type        = string
}

variable "app_port" {
  description = "Application port on EC2 instances."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB target group health check path."
  type        = string
  default     = "/health"
}

variable "ami_id" {
  description = "AMI ID for application EC2 instances."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for application tier."
  type        = string
  default     = "m7i.large"
}

variable "asg_min_size" {
  description = "Minimum number of app instances."
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Desired number of app instances."
  type        = number
  default     = 3

  validation {
    condition     = var.asg_desired_capacity >= var.asg_min_size && var.asg_desired_capacity <= var.asg_max_size
    error_message = "asg_desired_capacity must be between asg_min_size and asg_max_size."
  }
}

variable "asg_max_size" {
  description = "Maximum number of app instances."
  type        = number
  default     = 9
}

variable "db_engine" {
  description = "RDS engine. This stack is opinionated for PostgreSQL."
  type        = string
  default     = "postgres"

  validation {
    condition     = var.db_engine == "postgres"
    error_message = "This stack currently supports db_engine = \"postgres\" only."
  }
}

variable "db_engine_version" {
  description = "RDS engine version."
  type        = string
  default     = "16.3"
}

variable "db_parameter_group_family" {
  description = "RDS parameter group family."
  type        = string
  default     = "postgres16"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.m7g.large"
}

variable "db_allocated_storage" {
  description = "RDS initial allocated storage in GB."
  type        = number
  default     = 200
}

variable "db_max_allocated_storage" {
  description = "RDS autoscaling max storage in GB."
  type        = number
  default     = 1000
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "RDS master username."
  type        = string
  default     = "appadmin"
}

variable "db_backup_retention_days" {
  description = "RDS automated backup retention days."
  type        = number
  default     = 35
}

variable "db_port" {
  description = "Database port."
  type        = number
  default     = 5432
}

variable "redis_node_type" {
  description = "ElastiCache node type."
  type        = string
  default     = "cache.r7g.large"
}

variable "redis_engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.1"
}

variable "redis_port" {
  description = "Redis port."
  type        = number
  default     = 6379
}

variable "redis_auth_token" {
  description = "Optional Redis auth token (recommended to pass via secure pipeline variable)."
  type        = string
  default     = null
  sensitive   = true
}

variable "alarm_email_endpoint" {
  description = "Optional email endpoint for alarm notifications."
  type        = string
  default     = null
}

variable "enable_alb_access_logs" {
  description = "Enable ALB access logging to S3."
  type        = bool
  default     = true
}

variable "enable_vpc_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch Logs."
  type        = bool
  default     = true
}
