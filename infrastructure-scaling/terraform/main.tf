# Enterprise Infrastructure Scaling with Terraform
# Multi-region deployment with disaster recovery

terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    consul = {
      source  = "hashicorp/consul"
      version = "~> 2.18"
    }
    nomad = {
      source  = "hashicorp/nomad"
      version = "~> 1.4"
    }
  }
}

# Variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "regions" {
  description = "List of AWS regions for multi-region deployment"
  type        = list(string)
  default     = ["us-east-1", "us-west-2", "eu-west-1"]
}

variable "availability_zones" {
  description = "Availability zones per region"
  type        = map(list(string))
  default = {
    "us-east-1" = ["us-east-1a", "us-east-1b", "us-east-1c"]
    "us-west-2" = ["us-west-2a", "us-west-2b", "us-west-2c"]
    "eu-west-1" = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  }
}

variable "instance_types" {
  description = "Instance types for different workloads"
  type        = map(string)
  default = {
    "consul"    = "t3.medium"
    "nomad"     = "t3.large"
    "database"  = "r5.xlarge"
    "cache"     = "r5.large"
    "web"       = "t3.medium"
    "api"       = "t3.large"
    "worker"    = "c5.large"
  }
}

# Data sources
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Local values
locals {
  common_tags = {
    Environment = var.environment
    Project     = "nexus-v3"
    ManagedBy   = "terraform"
    Purpose     = "infrastructure-scaling"
  }
}

# Multi-region VPC setup
module "vpc" {
  source = "./modules/vpc"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region             = each.key
  environment        = var.environment
  availability_zones = var.availability_zones[each.key]
  
  tags = local.common_tags
}

# Auto Scaling Groups
module "auto_scaling" {
  source = "./modules/auto-scaling"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region          = each.key
  environment     = var.environment
  vpc_id          = module.vpc[each.key].vpc_id
  subnet_ids      = module.vpc[each.key].private_subnet_ids
  instance_types  = var.instance_types
  
  tags = local.common_tags
  
  depends_on = [module.vpc]
}

# Application Load Balancers
module "load_balancer" {
  source = "./modules/load-balancer"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region     = each.key
  environment = var.environment
  vpc_id     = module.vpc[each.key].vpc_id
  subnet_ids = module.vpc[each.key].public_subnet_ids
  
  tags = local.common_tags
  
  depends_on = [module.vpc]
}

# RDS Multi-AZ with Read Replicas
module "database" {
  source = "./modules/database"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region              = each.key
  environment         = var.environment
  vpc_id              = module.vpc[each.key].vpc_id
  subnet_ids          = module.vpc[each.key].private_subnet_ids
  primary_region      = var.regions[0]
  is_primary_region   = each.key == var.regions[0]
  
  tags = local.common_tags
  
  depends_on = [module.vpc]
}

# ElastiCache Redis Cluster
module "cache" {
  source = "./modules/cache"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region     = each.key
  environment = var.environment
  vpc_id     = module.vpc[each.key].vpc_id
  subnet_ids = module.vpc[each.key].private_subnet_ids
  
  tags = local.common_tags
  
  depends_on = [module.vpc]
}

# CloudFront for Edge Computing
module "edge_computing" {
  source = "./modules/edge-computing"
  
  environment    = var.environment
  regions        = var.regions
  load_balancers = { for k, v in module.load_balancer : k => v.dns_name }
  
  tags = local.common_tags
  
  depends_on = [module.load_balancer]
}

# Route53 for DNS and Health Checks
module "dns" {
  source = "./modules/dns"
  
  environment    = var.environment
  regions        = var.regions
  load_balancers = { for k, v in module.load_balancer : k => v.dns_name }
  
  tags = local.common_tags
  
  depends_on = [module.load_balancer]
}

# Monitoring and Alerting
module "monitoring" {
  source = "./modules/monitoring"
  
  for_each = toset(var.regions)
  
  providers = {
    aws = aws.region[each.key]
  }
  
  region      = each.key
  environment = var.environment
  
  tags = local.common_tags
}

# Outputs
output "vpc_ids" {
  description = "VPC IDs by region"
  value       = { for k, v in module.vpc : k => v.vpc_id }
}

output "load_balancer_dns" {
  description = "Load balancer DNS names by region"
  value       = { for k, v in module.load_balancer : k => v.dns_name }
}

output "database_endpoints" {
  description = "Database endpoints by region"
  value       = { for k, v in module.database : k => v.endpoint }
}

output "cache_endpoints" {
  description = "Cache endpoints by region"
  value       = { for k, v in module.cache : k => v.endpoint }
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain"
  value       = module.edge_computing.cloudfront_domain
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = module.dns.zone_id
}
