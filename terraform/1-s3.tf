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