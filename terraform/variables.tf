# variable "custom_domain" {
#   description = "Value of the custom domain"
#   type        = string
# }

# variable "admin_subdomain" {
#   description = "Value of the admin subdomain"
#   type        = string
# }

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
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

# variable "alarm_email_address" {
#   description = "Email address for alarm alerts"
#   type        = string
# }

# variable "stripe_publishable_key" {
#   description = "Stripe publishable key"
#   type        = string
# }

# variable "stripe_secret_key" {
#   description = "Stripe secret key"
#   type        = string
# }

# variable "rclc_username" {
#   description = "Red Cross Learning Center username"
#   type        = string
#   sensitive   = true
# }

# variable "rclc_password" {
#   description = "Red Cross Learning Center password"
#   type        = string
#   sensitive   = true
# }

# variable "twilio_account_sid" {
#   description = "Value of the Twilio SID"
#   type        = string
# }

# variable "twilio_auth_token" {
#   description = "Value of the Twilio auth token"
#   type        = string
# }

# variable "twilio_phone_number" {
#   description = "Value of the Twilio phone number"
#   type        = string
# }
