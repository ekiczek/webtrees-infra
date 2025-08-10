# S3 bucket for storing profile images
resource "aws_s3_bucket" "webtrees_media" {
  bucket = "${replace("webtrees_media", "_", "-")}-${random_string.bucket_suffix.result}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "webtrees_media_pab" {
  bucket = aws_s3_bucket.webtrees_media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# Upload migrated data files to S3 using AWS CLI sync
resource "null_resource" "upload_migrated_data" {
  provisioner "local-exec" {
    command = "aws s3 cp ../migrated_data/ s3://${aws_s3_bucket.webtrees_media.bucket}/ --recursive"
  }
  
  depends_on = [
    aws_s3_bucket.webtrees_media,
    aws_s3_bucket_public_access_block.webtrees_media_pab
  ]
  
  # Trigger re-sync when key files change
  triggers = {
    bucket_id = aws_s3_bucket.webtrees_media.id
    sql_file_hash = fileexists("../migrated_data/webtrees-data.sql") ? filemd5("../migrated_data/webtrees-data.sql") : "none"
  }
}

# Upload module files to S3 using AWS CLI sync
resource "null_resource" "upload_module_files" {
  provisioner "local-exec" {
    command = "aws s3 cp ../modules/ s3://${aws_s3_bucket.webtrees_media.bucket}/modules/ --recursive"
  }
  
  depends_on = [
    aws_s3_bucket.webtrees_media,
    aws_s3_bucket_public_access_block.webtrees_media_pab
  ]
  
  # Trigger re-sync when key files change
  # triggers = {
  #   bucket_id = aws_s3_bucket.webtrees_media.id
  #   sql_file_hash = fileexists("../migrated_data/webtrees-data.sql") ? filemd5("../migrated_data/webtrees-data.sql") : "none"
  # }
}

# Upload setup scripts to S3
resource "null_resource" "upload_scripts" {
  provisioner "local-exec" {
    command = "aws s3 cp scripts/ s3://${aws_s3_bucket.webtrees_media.bucket}/scripts/ --recursive"
  }
  
  depends_on = [
    aws_s3_bucket.webtrees_media,
    aws_s3_bucket_public_access_block.webtrees_media_pab
  ]
  
  triggers = {
    script_changes = filemd5("scripts/setup-webtrees.sh")
  }
}