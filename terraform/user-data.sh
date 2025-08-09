#!/bin/bash

# Update system
dnf update -yq

# Install Docker
dnf install -yq docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group
usermod -a -G docker ec2-user

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Install required packages for AWS CLI, Let's Encrypt, and cron
dnf install -yq unzip certbot cronie

# Enable and start cron service for Let's Encrypt certificate renewal
systemctl enable crond
systemctl start crond

# Install AWS CLI v2 (detect architecture)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  echo "Installing AWS CLI for ARM64 architecture..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
  echo "Installing AWS CLI for x86_64 architecture..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi
unzip -q awscliv2.zip
./aws/install
rm -rf aws awscliv2.zip

# Create directory for webtrees
mkdir -p /home/ec2-user/webtrees
chown ec2-user:ec2-user /home/ec2-user/webtrees

# Configure AWS CLI for ec2-user to use IAM role
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

# Set ownership
chown ec2-user:ec2-user /home/ec2-user/webtrees/docker-compose.yml

# Navigate to webtrees directory
cd /home/ec2-user/webtrees

# Start No-IP DUC service first for domain updates
echo "Starting No-IP DUC service to update ${domain_name} to point to $PUBLIC_IP..."
if [ ! -z "${noip_username}" ] && [ ! -z "${noip_password}" ]; then
  echo "Starting No-IP DUC service..."
  docker-compose up -d noip-duc
  
  echo "Waiting 60 seconds for initial No-IP domain update..."
  sleep 60
else
  echo "Warning: No-IP credentials not provided. Please manually update ${domain_name} to point to $PUBLIC_IP"
  echo "Waiting 30 seconds before proceeding..."
  sleep 30
fi

# Generate Let's Encrypt certificate using standalone method
echo "Attempting Let's Encrypt certificate for ${domain_name}..."

# Create certificates directory
mkdir -p /home/ec2-user/webtrees/certs

# Try to get Let's Encrypt certificate and capture the exit code
if certbot certonly --standalone \
  --email ${letsencrypt_email} \
  --agree-tos \
  --no-eff-email \
  --domains ${domain_name} \
  --non-interactive; then
  
  # Success - copy Let's Encrypt certificates
  echo "Let's Encrypt certificate successfully generated!"
  cp /etc/letsencrypt/live/${domain_name}/fullchain.pem /home/ec2-user/webtrees/certs/webtrees.crt
  cp /etc/letsencrypt/live/${domain_name}/privkey.pem /home/ec2-user/webtrees/certs/webtrees.key
  echo "Let's Encrypt certificates copied to webtrees directory."
else
  # Failed - fall back to self-signed certificate
  echo "Let's Encrypt certificate generation failed (likely rate limited or DNS issues)."
  echo "Falling back to self-signed certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /home/ec2-user/webtrees/certs/webtrees.key \
    -out /home/ec2-user/webtrees/certs/webtrees.crt \
    -subj "/C=US/ST=State/L=City/O=Webtrees/OU=IT/CN=${domain_name}"
  echo "Self-signed certificate created. Browsers will show a security warning."
fi

chown -R ec2-user:ec2-user /home/ec2-user/webtrees/certs
chmod 600 /home/ec2-user/webtrees/certs/webtrees.key
chmod 644 /home/ec2-user/webtrees/certs/webtrees.crt

# Start MariaDB container
echo "Starting MariaDB container..."
docker-compose up -d mariadb

# Wait for MariaDB to be ready
echo "Waiting for MariaDB to be ready..."
until docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} -e "SELECT 1;" > /dev/null 2>&1; do
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
    echo "Creating ${db_database_name} database..."
    docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} -e "CREATE DATABASE IF NOT EXISTS ${db_database_name};"
    
    echo "Importing database from $SQL_FILE..."
    docker exec -i webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} < "$LOCAL_SQL_PATH"
    
    if [ $? -eq 0 ]; then
      echo "Database import successful!"
      
      # Clean up: delete from S3 and local
      echo "Cleaning up: removing $SQL_FILE from S3 and local filesystem..."
      # aws s3 rm "s3://$S3_BUCKET/$SQL_FILE"
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

  # Programatically enable S3 module
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module (module_name, status) VALUES ('_webtrees_s3_media_', 'enabled') ON DUPLICATE KEY UPDATE status = 'enabled';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_bucket', '$S3_BUCKET') ON DUPLICATE KEY UPDATE setting_name = 's3_bucket', setting_value = '$S3_BUCKET';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_enabled', '1') ON DUPLICATE KEY UPDATE setting_name = 's3_enabled', setting_value = '1';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_endpoint', '') ON DUPLICATE KEY UPDATE setting_name = 's3_endpoint', setting_value = '';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_key', '') ON DUPLICATE KEY UPDATE setting_name = 's3_key', setting_value = '';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_media_prefix', 'media/') ON DUPLICATE KEY UPDATE setting_name = 's3_media_prefix', setting_value = 'media/';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_path_style', '0') ON DUPLICATE KEY UPDATE setting_name = 's3_path_style', setting_value = '0';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_region', '${aws_region}') ON DUPLICATE KEY UPDATE setting_name = 's3_region', setting_value = '${aws_region}';"
  docker exec webtrees_mariadb /usr/bin/mariadb -u ${db_username} --password=${db_password} ${db_database_name} -e "INSERT INTO wt_module_setting (module_name, setting_name, setting_value) VALUES ('_webtrees_s3_media_', 's3_secret', '') ON DUPLICATE KEY UPDATE setting_name = 's3_secret', setting_value = '';"
else
  echo "No $MODULES_PATH found in S3 bucket. Skipping database import."
fi

# Set up automatic certificate renewal
echo "Setting up automatic certificate renewal..."
echo "0 12 * * * /usr/bin/certbot renew --quiet --post-hook 'cp /etc/letsencrypt/live/${domain_name}/fullchain.pem /home/ec2-user/webtrees/certs/webtrees.crt && cp /etc/letsencrypt/live/${domain_name}/privkey.pem /home/ec2-user/webtrees/certs/webtrees.key && cd /home/ec2-user/webtrees && docker-compose restart webtrees'" | crontab -

# Start webtrees container
echo "Starting webtrees container..."
docker-compose up -d webtrees

echo "Disabling ImageMagick because it's been problematic. Fallback to GD..."
docker exec webtrees bash -c "mv /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini.bak"

echo "Restarting webtrees with ImageMagick/GD fixes..."
docker-compose restart webtrees

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
echo "--- No-IP DUC ---"
docker-compose logs --tail=20 noip_duc

echo -e "\n=== Container Logs (last 20 lines) ==="
echo "--- Webtrees ---"
docker-compose logs --tail=20 webtrees

echo -e "\n--- MariaDB ---"
docker-compose logs --tail=20 mariadb
STATUS_EOF

# Make status.sh executable and set ownership
chmod +x /home/ec2-user/webtrees/status.sh
chown ec2-user:ec2-user /home/ec2-user/webtrees/status.sh

# Re-set ownership because initial webtrees launch re-sets the permissions for some reason
# chown ec2-user:ec2-user /home/ec2-user/webtrees/config.ini.php
