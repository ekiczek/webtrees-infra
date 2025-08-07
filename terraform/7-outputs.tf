# Outputs
output "webtrees_url" {
  description = "URL to access the webtrees application"
  value       = "https://${var.domain_name}"
}

output "webtrees_ssh_command" {
  description = "SSH command to connect to the webtrees instance"
  value       = "ssh ec2-user@${aws_instance.webtrees_instance.public_ip}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for webtrees media"
  value       = aws_s3_bucket.webtrees_media.bucket
}

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.webtrees_instance.id
}

output "public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.webtrees_instance.public_ip
}