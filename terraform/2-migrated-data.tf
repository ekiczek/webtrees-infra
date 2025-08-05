locals {
  content_types = {
    ".jpeg" : "image/jpeg"
    ".jpg" : "image/jpeg"
    ".mp4" : "video/mp4"
    ".png" : "image/png"
    ".zip" : "application/zip"
    ".pdf" : "application/pdf"
  }
}

resource "aws_s3_object" "migrated_file" {
  for_each     = fileset(path.module, "../migrated_data/**/*")
  bucket       = aws_s3_bucket.webtrees_media.id
  key          = replace(each.value, "/^../migrated_data//", "")
  source       = each.value
  content_type = lookup(local.content_types, regex("\\.[^.]+$", each.value), null)
  source_hash  = filemd5(each.value)

  depends_on   = [ aws_s3_bucket.webtrees_media ]
}
