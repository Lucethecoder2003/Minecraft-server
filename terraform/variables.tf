variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "minecraft"
}

variable "instance_type" {
  description = "EC2 instance type (t3.medium recommended for Minecraft)"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 10
}

variable "public_key_path" {
  description = "Path to the SSH public key to install on the instance"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed SSH access (restrict to your IP for security)"
  type        = string
  default     = "0.0.0.0/0"
}
