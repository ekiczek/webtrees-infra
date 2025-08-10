# Outputs
output "webtrees_url" {
  description = "URL to access the webtrees application"
  value       = "https://${var.domain_name}"
}

output "webtrees_ssh_command" {
  description = "SSH command to connect to the webtrees instance"
  value       = "ssh ec2-user@${aws_instance.webtrees_instance.public_ip}"
}

output "webtrees_tail_cloud_init_logs" {
  description = "SSH command to connect to the webtrees instance"
  value       = "ssh ec2-user@${aws_instance.webtrees_instance.public_ip} 'sudo tail -f /var/log/cloud-init.log /var/log/cloud-init-output.log'"
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

# Database backup commands
output "backup_database_command" {
  description = "One-liner to backup database to S3 (copy and paste into terminal)"
  value       = <<-EOT
ssh -t ec2-user@${aws_instance.webtrees_instance.public_ip} "docker exec webtrees_mariadb mariadb-dump -u ${var.db_username} --password='${var.db_password}' ${var.db_database_name} > /tmp/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://${aws_s3_bucket.webtrees_media.bucket}/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://${aws_s3_bucket.webtrees_media.bucket}/backups/webtrees-data-\$(date +%Y%m%d-%H%M%S).sql && rm /tmp/webtrees-data.sql && echo 'Backup completed: webtrees-data.sql and timestamped copy saved to S3'"
  EOT
  sensitive   = true
  # Note: Contains database password - use 'terraform output -raw backup_database_command' to view
}

output "restore_database_command" {
  description = "One-liner to restore database from S3 (copy and paste into terminal)"
  value       = <<-EOT
ssh -t ec2-user@${aws_instance.webtrees_instance.public_ip} "aws s3 cp s3://${aws_s3_bucket.webtrees_media.bucket}/webtrees-data.sql /tmp/webtrees-data.sql && docker exec -i webtrees_mariadb mariadb -u ${var.db_username} --password='${var.db_password}' ${var.db_database_name} < /tmp/webtrees-data.sql && rm /tmp/webtrees-data.sql && echo 'Database restored from S3'"
  EOT
  sensitive   = true
  # Note: Contains database password - use 'terraform output -raw restore_database_command' to view
}

# Helper text for database operations
output "database_operations_help" {
  description = "How to use database backup/restore commands"
  value = <<-EOT

DATABASE OPERATIONS:
====================
To view and use the backup/restore commands, run:

  Backup:  terraform output -raw backup_database_command
  Restore: terraform output -raw restore_database_command

The backup creates:
  - s3://${aws_s3_bucket.webtrees_media.bucket}/webtrees-data.sql (latest)
  - s3://${aws_s3_bucket.webtrees_media.bucket}/backups/webtrees-data-TIMESTAMP.sql (archived)
  EOT
}