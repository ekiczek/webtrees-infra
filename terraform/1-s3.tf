# S3 bucket for storing profile images
resource "aws_s3_bucket" "webtrees_media" {
  bucket = "${replace("webtrees_media", "_", "-")}-${random_string.bucket_suffix.result}"

  tags = var.tags
}

resource "aws_s3_bucket_public_access_block" "webtrees_media_pab" {
  bucket = aws_s3_bucket.webtrees_media.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "webtrees_media_policy" {
  bucket = aws_s3_bucket.webtrees_media.id
  depends_on = [aws_s3_bucket_public_access_block.webtrees_media_pab]

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*"
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "${aws_s3_bucket.webtrees_media.arn}",
                "${aws_s3_bucket.webtrees_media.arn}/*"
            ]
        }
    ]
  })
}

# resource "aws_s3_bucket_cors_configuration" "webtrees_media_cors" {
#   bucket = aws_s3_bucket.webtrees_media.id

#   cors_rule {
#     allowed_headers = ["*"]
#     allowed_methods = ["GET", "PUT", "POST"]
#     allowed_origins = ["*"]
#     expose_headers  = ["ETag"]
#     max_age_seconds = 3000
#   }
# }

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}