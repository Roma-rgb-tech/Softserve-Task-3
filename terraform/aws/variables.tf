variable "aws_region" {
  description = "AWS region for infrastructure deployment"
  type        = string
  default     = "eu-north-1"
}

variable "environment" {
  description = "Environment name for naming and tagging"
  type        = string
  default     = "Dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the main VPC"
  type        = string
  default     = "10.0.0.0/24"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.0.0/27", "10.0.0.32/27"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private application subnets"
  type        = list(string)
  default     = ["10.0.0.64/27", "10.0.0.96/27"]
}

variable "db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets"
  type        = list(string)
  default     = ["10.0.0.128/27", "10.0.0.160/27"]
}

variable "availability_zones" {
  description = "Availability zones for high availability deployment"
  type        = list(string)
  default     = ["eu-north-1a", "eu-north-1b"]
}

variable "enable_nat_gateway" {
  description = "Enable or disable NAT Gateway creation"
  type        = bool
  default     = true
}

variable "admin_cidr" {
  description = "Admin IP allowed to SSH into the bastion, in x.x.x.x/32 format"
  type        = string

  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be a single IP in /32 format."
  }
}

variable "ssh_public_key" {
  description = "Public SSH key for the bastion and private instances"
  type        = string
}

variable "bastion_instance_type" {
  description = "Instance type for the bastion host"
  type        = string
  default     = "t3.nano"
}

variable "app_instance_type" {
  description = "Instance type for LLM instances in the ASG"
  type        = string
  default     = "c7i.large"
}

variable "db_instance_type" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_instance_class" {
  description = "RDS isntance type"
  type        = string
  default     = "db.t3.micro"
}

variable "monitoring_instance_type" {
  description = "Instance type for the monitoring host"
  type        = string
  default     = "t3.small"
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack incoming webhook URL for Alertmanager"
  type        = string
  sensitive   = true
}

variable "open_webui_instance_type" {
  description = "Instance type for Open WebUI host"
  type        = string
  default     = "t3.small"
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone"
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "domain_name must be a lowercase domain name without a trailing dot, for example example.pp.ua"
  }
}

variable "route53_delegation_set_id" {
  description = "Reusable delegation set ID so the hosted zone keeps the same name servers"
  type        = string
}

variable "keycloak_instance_type" {
  description = "EC2 instance type for Keycloak"
  type        = string
  default     = "t3.small"
}

variable "vpn_cidrs" {
  description = "Public egress CIDRs of the corporate VPN allowed to reach the web ALB"
  type        = list(string)
}

variable "keycloak_realm" {
  description = "Keycloak realm that Open WebUI users sign in to"
  type        = string
  default     = "softserve"
}

variable "ollama_num_parallel" {
  description = "Number of chat messages each Ollam instance generates at the same time"
  type        = number
  default     = 2
}

variable "ollama_max_queue" {
  description = "Maximum number of messages waiting on each Ollama instance before it answers 503"
  type        = number
  default     = 10
}

variable "ollama_num_thread" {
  description = "CPU threads Ollama uses for generation, equal to the vCPU count of the instance type"
  type        = number
  default     = 2
}

variable "keycloak_admin_password" {
  description = "Keycloak bootstrap admin password, kept stable so a restored database still accepts it"
  type        = string
  sensitive   = true
}

variable "open_webui_secret_key" {
  description = "Open WebUI JWT signing key, kept stable so user sessions survive a rebuild"
  type        = string
  sensitive   = true
}
