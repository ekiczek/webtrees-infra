variable "aws_region" {
  description = "AWS Region"
  type        = string
  default    = "us-east-2"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ec2_instance_type" {
  description = "EC2 instance type"
  type        = string
  default    = "t4g.small"  # ARM-based, 2 vCPU, 2 GB RAM
}

variable "ec2_ssh_key_name" {
  description = "Name of EC2 key pair for SSH access"
  type        = string
}

variable "domain_name" {
  description = "Domain name for webtrees"
  type        = string
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt notifications"
  type        = string
}

variable "noip_username" {
  description = "No-IP username for domain updates"
  type        = string
  sensitive   = true
}

variable "noip_password" {
  description = "No-IP password for domain updates" 
  type        = string
  sensitive   = true
}

variable "db_database_name" {
  description = "Database name" 
  type        = string
  default     = "webtrees"
}

variable "db_table_prefix" {
  description = "Database table prefix" 
  type        = string
  default     = "wt_"
}

variable "db_username" {
  description = "Database username" 
  type        = string
  default     = "webtrees"
  sensitive   = true
}

variable "db_password" {
  description = "Database password" 
  type        = string
  default     = "webtrees_password"
  sensitive   = true
}

variable "webtrees_container_tag" {
  description = "Webtrees Docker container tag" 
  type        = string
  default     = "latest"
}

variable "mariadb_container_tag" {
  description = "Webtrees Docker container tag" 
  type        = string
  default     = "10.11"
}
