# IAM Role for EC2 instance to access S3
resource "aws_iam_role" "webtrees_ec2_role" {
  name = "webtrees-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM Policy for S3 access
resource "aws_iam_role_policy" "webtrees_s3_policy" {
  name = "webtrees-s3-policy"
  role = aws_iam_role.webtrees_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetObjectVersion",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          aws_s3_bucket.webtrees_media.arn,
          "${aws_s3_bucket.webtrees_media.arn}/*"
        ]
      }
    ]
  })
}

# Instance Profile for EC2
resource "aws_iam_instance_profile" "webtrees_profile" {
  name = "webtrees-profile"
  role = aws_iam_role.webtrees_ec2_role.name

  tags = var.tags
}

# Data source to get the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Security Group for EC2 instance
resource "aws_security_group" "webtrees_ec2_sg" {
  name        = "webtrees-ec2-sg"
  description = "Security group for webtrees EC2 instance"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS access
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "webtrees-ec2-sg"
  })
}

# EC2 Instance
resource "aws_instance" "webtrees_instance" {
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t3.micro"
  key_name             = var.ec2_ssh_key_name
  iam_instance_profile = aws_iam_instance_profile.webtrees_profile.name
  
  security_groups = [aws_security_group.webtrees_ec2_sg.name]
  
  user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
    s3_bucket = aws_s3_bucket.webtrees_media.bucket
  }))

  tags = merge(var.tags, {
    Name = "webtrees-instance"
  })
}