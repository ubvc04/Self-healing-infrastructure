variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must not be empty."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.40.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 1))
    error_message = "vpc_cidr must be a valid CIDR block."
  }
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.40.1.0/24", "10.40.2.0/24", "10.40.3.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 3
    error_message = "public_subnet_cidrs must contain at least 3 subnets."
  }

  validation {
    condition     = alltrue([for c in var.public_subnet_cidrs : can(cidrhost(c, 1))])
    error_message = "Each value in public_subnet_cidrs must be a valid CIDR block."
  }
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"

  validation {
    condition     = length(trimspace(var.instance_type)) > 0
    error_message = "instance_type must not be empty."
  }
}

variable "ssh_ingress_cidr" {
  description = "CIDR allowed to SSH"
  type        = string
  default     = ""

  validation {
    condition     = var.ssh_ingress_cidr != "" && can(cidrhost(var.ssh_ingress_cidr, 1))
    error_message = "ssh_ingress_cidr must be a valid CIDR block (for example, 203.0.113.10/32)."
  }
}

variable "public_key" {
  description = "SSH public key material"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.public_key)) > 0
    error_message = "public_key must not be empty."
  }
}

variable "node_count" {
  description = "Total node count including control plane"
  type        = number
  default     = 3

  validation {
    condition     = var.node_count >= 3
    error_message = "node_count must be at least 3."
  }

  validation {
    condition     = var.node_count <= 15
    error_message = "node_count must be less than or equal to 15 to avoid accidental over-provisioning."
  }
}

variable "ami_id" {
  description = "Optional AMI ID override"
  type        = string
  default     = ""
}
