# SES Email Configuration for Webtrees
# Creates SES domain identity, DNS verification records, DKIM, and SMTP credentials

# Look up the existing Route 53 hosted zone for the SES domain
data "aws_route53_zone" "ses_domain" {
  count = var.ses_domain != "" ? 1 : 0
  name  = var.ses_domain
}

# SES Domain Identity
resource "aws_ses_domain_identity" "this" {
  count  = var.ses_domain != "" ? 1 : 0
  domain = var.ses_domain
}

# Route 53 TXT record for SES domain verification
resource "aws_route53_record" "ses_verification" {
  count   = var.ses_domain != "" ? 1 : 0
  zone_id = data.aws_route53_zone.ses_domain[0].zone_id
  name    = "_amazonses.${var.ses_domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this[0].verification_token]
}

# DKIM for SES domain
resource "aws_ses_domain_dkim" "this" {
  count  = var.ses_domain != "" ? 1 : 0
  domain = aws_ses_domain_identity.this[0].domain
}

# Route 53 CNAME records for DKIM
resource "aws_route53_record" "ses_dkim" {
  count   = var.ses_domain != "" ? 3 : 0
  zone_id = data.aws_route53_zone.ses_domain[0].zone_id
  name    = "${aws_ses_domain_dkim.this[0].dkim_tokens[count.index]}._domainkey.${var.ses_domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_ses_domain_dkim.this[0].dkim_tokens[count.index]}.dkim.amazonses.com"]
}

# IAM user for SMTP authentication
resource "aws_iam_user" "ses_smtp" {
  count = var.ses_domain != "" ? 1 : 0
  name  = "webtrees-ses-smtp"

  tags = var.tags
}

# IAM policy allowing ses:SendRawEmail restricted to the domain identity
resource "aws_iam_user_policy" "ses_smtp" {
  count = var.ses_domain != "" ? 1 : 0
  name  = "webtrees-ses-send"
  user  = aws_iam_user.ses_smtp[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "ses:SendRawEmail"
        Resource = aws_ses_domain_identity.this[0].arn
      }
    ]
  })
}

# IAM access key — Terraform derives the SMTP password from the secret
resource "aws_iam_access_key" "ses_smtp" {
  count = var.ses_domain != "" ? 1 : 0
  user  = aws_iam_user.ses_smtp[0].name
}
