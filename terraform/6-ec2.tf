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
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"
  key_name      = var.ec2_ssh_key_name
  
  security_groups = [aws_security_group.webtrees_ec2_sg.name]
  
  user_data_base64 = base64encode(templatefile("${path.module}/user-data.sh", {
    s3_bucket = aws_s3_bucket.webtrees_media.bucket
  }))

  tags = merge(var.tags, {
    Name = "webtrees-instance"
  })
}