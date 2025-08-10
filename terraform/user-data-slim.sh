#!/bin/bash

# Update system
dnf update -yq

# Install Docker
dnf install -yq docker

# Configure Docker daemon with log limits
cat > /etc/docker/daemon.json << 'DOCKER_CONFIG_EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DOCKER_CONFIG_EOF

systemctl start docker
systemctl enable docker
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install required packages
dnf install -yq unzip certbot cronie amazon-cloudwatch-agent

# Enable and start cron service
systemctl enable crond
systemctl start crond

# Install AWS CLI v2 (detect architecture)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create directory for webtrees
mkdir -p /home/ec2-user/webtrees
chown ec2-user:ec2-user /home/ec2-user/webtrees

# Configure AWS CLI
mkdir -p /home/ec2-user/.aws
cat > /home/ec2-user/.aws/config << AWS_CONFIG_EOF
[default]
region = ${aws_region}
output = json
AWS_CONFIG_EOF
chown -R ec2-user:ec2-user /home/ec2-user/.aws

# Get the public IP from instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Create webtrees config.ini.php
cat > /home/ec2-user/webtrees/config.ini.php << CONFIG_EOF
; <?php return; ?> DO NOT DELETE THIS LINE
dbtype="mysql"
dbhost="mariadb"
dbport="3306"
dbuser="${db_username}"
dbpass="${db_password}"
dbname="${db_database_name}"
tblpfx="${db_table_prefix}"
base_url="https://${domain_name}"
CONFIG_EOF

# Create docker-compose.yml
cat > /home/ec2-user/webtrees/docker-compose.yml << COMPOSE_EOF
services:
  noip-duc:
    image: ghcr.io/noipcom/noip-duc:latest
    container_name: noip_duc
    environment:
      - NOIP_USERNAME=${noip_username}
      - NOIP_PASSWORD=${noip_password}
      - NOIP_HOSTNAMES=${domain_name}
    network_mode: host
    restart: unless-stopped

  webtrees:
    image: nathanvaughn/webtrees:${webtrees_container_tag}
    container_name: webtrees
    ports:
      - "80:80"
      - "443:443"
    environment:
      - LANG=en_US.UTF-8
      - AWS_DEFAULT_REGION=${aws_region}
      - S3_BUCKET_NAME=${s3_bucket}
      - HTTPS=1
      - HTTPS_REDIRECT=1
      - PRETTY_URLS=True
    volumes:
      - ./config.ini.php:/var/www/webtrees/data/config.ini.php
      - /home/ec2-user/webtrees/modules_v4:/var/www/webtrees/modules_v4
      - webtrees_data:/var/www/webtrees/data
      - webtrees_media:/var/www/webtrees/media
      - /home/ec2-user/.aws:/var/www/.aws:ro
      - ./certs:/certs
    depends_on:
      - mariadb
    restart: unless-stopped

  mariadb:
    image: mariadb:${mariadb_container_tag}
    container_name: webtrees_mariadb
    environment:
      - MYSQL_ROOT_PASSWORD=root_password
      - MYSQL_DATABASE=${db_database_name}
      - MYSQL_USER=${db_username}
      - MYSQL_PASSWORD=${db_password}
    volumes:
      - mariadb_data:/var/lib/mysql
    restart: unless-stopped

volumes:
  webtrees_data:
  webtrees_media:
  mariadb_data:
COMPOSE_EOF

chown ec2-user:ec2-user /home/ec2-user/webtrees/config.ini.php /home/ec2-user/webtrees/docker-compose.yml

# Download and run setup scripts
cd /home/ec2-user/webtrees

# Download additional scripts (these will be uploaded to S3)
aws s3 cp s3://${s3_bucket}/scripts/ . --recursive

# Make scripts executable
chmod +x *.sh
chown ec2-user:ec2-user *.sh

# Set environment variables for setup script
export DB_USERNAME="${db_username}"
export DB_PASSWORD="${db_password}"
export DB_NAME="${db_database_name}"
export DOMAIN_NAME="${domain_name}"
export LETSENCRYPT_EMAIL="${letsencrypt_email}"
export NOIP_USERNAME="${noip_username}"
export NOIP_PASSWORD="${noip_password}"
export S3_BUCKET="${s3_bucket}"

# Continue with setup
bash setup-webtrees.sh

echo "Setup complete! Webtrees should be accessible at https://${domain_name}"
echo "Monitoring configured - check CloudWatch dashboard for metrics"