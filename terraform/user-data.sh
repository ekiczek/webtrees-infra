#!/bin/bash

# Update system
dnf update -y

# Install Docker
dnf install -y docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install unzip (required for AWS CLI installation)
dnf install -y unzip

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create directory for webtrees
mkdir -p /home/ec2-user/webtrees
chown ec2-user:ec2-user /home/ec2-user/webtrees

# Configure AWS CLI for ec2-user to use IAM role
mkdir -p /home/ec2-user/.aws
cat > /home/ec2-user/.aws/config << 'AWS_CONFIG_EOF'
[default]
region = us-east-2
output = json
AWS_CONFIG_EOF
chown -R ec2-user:ec2-user /home/ec2-user/.aws

# Get the public IP from instance metadata
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
PUBLIC_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Create config.ini.php
cat > /home/ec2-user/webtrees/config.ini.php << CONFIG_EOF
; <?php return; ?> DO NOT DELETE THIS LINE
dbtype="mysql"
dbhost="mariadb"
dbport="3306"
dbuser="webtrees"
dbpass="webtrees_password"
dbname="webtrees"
tblpfx="wt_"
base_url="http://$${PUBLIC_IP}"
rewrite_urls="0"
CONFIG_EOF

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/webtrees/config.ini.php

# Create docker-compose.yml with substituted PUBLIC_IP
cat > /home/ec2-user/webtrees/docker-compose.yml << COMPOSE_EOF
services:
  webtrees:
    image: nathanvaughn/webtrees:latest
    container_name: webtrees
    ports:
      - "80:80"
    environment:
      - LANG=en_US.UTF-8
      - DB_HOST=mariadb
      - DB_PORT=3306
      - DB_USER=webtrees
      - DB_PASS=webtrees_password
      - DB_NAME=webtrees
      - BASE_URL=http://$${PUBLIC_IP}
      - AWS_DEFAULT_REGION=us-east-2
      - S3_BUCKET_NAME=${s3_bucket}
    volumes:
      - ./config.ini.php:/var/www/webtrees/data/config.ini.php
      - /home/ec2-user/webtrees/modules_v4:/var/www/webtrees/modules_v4
      - webtrees_data:/var/www/webtrees/data
      - webtrees_media:/var/www/webtrees/media
      - /home/ec2-user/.aws:/var/www/.aws:ro
    depends_on:
      - mariadb
    restart: unless-stopped

  mariadb:
    image: mariadb:10.11
    container_name: webtrees_mariadb
    environment:
      - MYSQL_ROOT_PASSWORD=root_password
      - MYSQL_DATABASE=webtrees
      - MYSQL_USER=webtrees
      - MYSQL_PASSWORD=webtrees_password
    volumes:
      - mariadb_data:/var/lib/mysql
    restart: unless-stopped

volumes:
  webtrees_data:
  webtrees_media:
  mariadb_data:
COMPOSE_EOF

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/webtrees/docker-compose.yml

# Navigate to webtrees directory
cd /home/ec2-user/webtrees

# Start MariaDB container first
echo "Starting MariaDB container..."
docker-compose up -d mariadb

# Wait for MariaDB to be ready
echo "Waiting for MariaDB to be ready..."
until docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MariaDB not ready yet, waiting 5 seconds..."
  sleep 5
done
echo "MariaDB is ready!"

# Check for webtrees-data.sql in S3 bucket and import if exists
S3_BUCKET="${s3_bucket}"
SQL_FILE="webtrees-data.sql"
LOCAL_SQL_PATH="/home/ec2-user/webtrees/$SQL_FILE"

echo "Checking for $SQL_FILE in S3 bucket $S3_BUCKET..."
if aws s3 ls "s3://$S3_BUCKET/$SQL_FILE" > /dev/null 2>&1; then
  echo "Found $SQL_FILE in S3 bucket. Downloading..."
  aws s3 cp "s3://$S3_BUCKET/$SQL_FILE" "$LOCAL_SQL_PATH"
  
  if [ -f "$LOCAL_SQL_PATH" ]; then
    echo "Creating webtrees database..."
    docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password -e "CREATE DATABASE IF NOT EXISTS webtrees;"
    
    echo "Importing database from $SQL_FILE..."
    docker exec -i webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees < "$LOCAL_SQL_PATH"
    
    if [ $? -eq 0 ]; then
      echo "Database import successful!"
      
      # Clean up: delete from S3 and local
      echo "Cleaning up: removing $SQL_FILE from S3 and local filesystem..."
      aws s3 rm "s3://$S3_BUCKET/$SQL_FILE"
      rm -f "$LOCAL_SQL_PATH"
      echo "Cleanup completed."
    else
      echo "Database import failed!"
    fi
  else
    echo "Failed to download $SQL_FILE from S3."
  fi
else
  echo "No $SQL_FILE found in S3 bucket. Skipping database import."
fi

# Check for modules in S3 bucket and copy if they exist
S3_BUCKET="${s3_bucket}"
MODULES_PATH="modules"
LOCAL_MODULES_PATH="/home/ec2-user/webtrees/modules_v4"

echo "Checking for $MODULES_PATH in S3 bucket $S3_BUCKET..."
if aws s3 ls "s3://$S3_BUCKET/$MODULES_PATH" > /dev/null 2>&1; then
  echo "Found $MODULES_PATH in S3 bucket. Downloading..."
  aws s3 cp "s3://$S3_BUCKET/$MODULES_PATH" "$LOCAL_MODULES_PATH" --recursive
  chown -R ec2-user:ec2-user "$LOCAL_MODULES_PATH"

  echo "Cleaning up: removing $MODULES_PATH from S3..."
  aws s3 rm "s3://$S3_BUCKET/$MODULES_PATH" --recursive
  echo "Cleanup completed."

  # Programatically enable S3 module
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module (module_name, status) VALUES ('_webtrees_s3_media_', 'enabled') ON DUPLICATE KEY UPDATE status = 'enabled';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_bucket', '$S3_BUCKET') ON DUPLICATE KEY UPDATE setting_name = 's3_bucket', setting_value = '$S3_BUCKET';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_enabled', '1') ON DUPLICATE KEY UPDATE setting_name = 's3_enabled', setting_value = '1';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_endpoint', '') ON DUPLICATE KEY UPDATE setting_name = 's3_endpoint', setting_value = '';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_key', '') ON DUPLICATE KEY UPDATE setting_name = 's3_key', setting_value = '';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_media_prefix', 'media/') ON DUPLICATE KEY UPDATE setting_name = 's3_media_prefix', setting_value = 'media/';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_path_style', '0') ON DUPLICATE KEY UPDATE setting_name = 's3_path_style', setting_value = '0';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_region', 'us-east-2') ON DUPLICATE KEY UPDATE setting_name = 's3_region', setting_value = 'us-east-2';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u webtrees --password=webtrees_password webtrees -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_secret', '') ON DUPLICATE KEY UPDATE setting_name = 's3_secret', setting_value = '';"
else
  echo "No $MODULES_PATH found in S3 bucket. Skipping database import."
fi

# Start webtrees container
echo "Starting webtrees container..."
docker-compose up -d webtrees

# Install Composer and module dependencies
docker exec webtrees bash -c "
    curl -sS https://getcomposer.org/installer | php && 
    mv composer.phar /usr/local/bin/composer && 
    chmod +x /usr/local/bin/composer &&
    cd /var/www/webtrees/modules_v4/webtrees_s3_media &&
    composer install --no-dev --optimize-autoloader
"

# Create a simple status script
cat > /home/ec2-user/webtrees/status.sh << STATUS_EOF
#!/bin/bash
echo "=== Container Status ==="
docker-compose ps

echo -e "\n=== Container Logs (last 20 lines) ==="
echo "--- Webtrees ---"
docker-compose logs --tail=20 webtrees

echo -e "\n--- MariaDB ---"
docker-compose logs --tail=20 mariadb
STATUS_EOF

# Make status.sh executable and set ownership
chmod +x /home/ec2-user/webtrees/status.sh
chown ec2-user:ec2-user /home/ec2-user/webtrees/status.sh