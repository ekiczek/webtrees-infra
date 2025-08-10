#!/bin/bash
# Main webtrees setup script

set -e

# Get configuration from environment
DB_USERNAME=${DB_USERNAME:-webtrees}
DB_PASSWORD=${DB_PASSWORD:-webtrees_password}
DB_NAME=${DB_NAME:-webtrees}
DOMAIN_NAME=${DOMAIN_NAME}
S3_BUCKET=${S3_BUCKET}
NOIP_USERNAME=${NOIP_USERNAME}
NOIP_PASSWORD=${NOIP_PASSWORD}
LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL}

echo "Starting webtrees setup..."
cd /home/ec2-user/webtrees

# Start No-IP DUC service first for domain updates  
if [ ! -z "${NOIP_USERNAME}" ] && [ ! -z "${NOIP_PASSWORD}" ]; then
  echo "Starting No-IP DUC service..."
  docker-compose up -d noip-duc
  sleep 60
else
  echo "Warning: No-IP credentials not provided."
  sleep 30
fi

# Create certificates directory and generate Let's Encrypt certificate
mkdir -p certs

echo "Attempting Let's Encrypt certificate for ${DOMAIN_NAME}..."
if certbot certonly --standalone \
  --email ${LETSENCRYPT_EMAIL} \
  --agree-tos \
  --no-eff-email \
  --domains ${DOMAIN_NAME} \
  --non-interactive; then
  
  echo "Let's Encrypt certificate successfully generated!"
  cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem certs/webtrees.crt
  cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem certs/webtrees.key
else
  echo "Let's Encrypt failed. Using self-signed certificate..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout certs/webtrees.key \
    -out certs/webtrees.crt \
    -subj "/C=US/ST=State/L=City/O=Webtrees/OU=IT/CN=${DOMAIN_NAME}"
fi

chown -R ec2-user:ec2-user certs
chmod 600 certs/webtrees.key
chmod 644 certs/webtrees.crt

# Start MariaDB container
echo "Starting MariaDB container..."
docker-compose up -d mariadb

# Wait for MariaDB to be ready
echo "Waiting for MariaDB to be ready..."
until docker exec webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MariaDB not ready yet, waiting 5 seconds..."
  sleep 5
done
echo "MariaDB is ready!"

# Check for webtrees-data.sql in S3 bucket and import if exists
SQL_FILE="webtrees-data.sql"
if aws s3 ls "s3://$S3_BUCKET/$SQL_FILE" > /dev/null 2>&1; then
  echo "Found $SQL_FILE in S3 bucket. Downloading..."
  aws s3 cp "s3://$S3_BUCKET/$SQL_FILE" "/tmp/$SQL_FILE"
  
  if [ -f "/tmp/$SQL_FILE" ]; then
    echo "Importing database from $SQL_FILE..."
    docker exec -i webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD $DB_NAME < "/tmp/$SQL_FILE"
    rm -f "/tmp/$SQL_FILE"
    echo "Database import successful!"
  fi
fi

# Check for modules in S3 bucket  
if aws s3 ls "s3://$S3_BUCKET/modules" > /dev/null 2>&1; then
  echo "Found modules in S3 bucket. Downloading..."
  aws s3 cp "s3://$S3_BUCKET/modules" "modules_v4" --recursive
  chown -R ec2-user:ec2-user modules_v4
fi

# Set up certificate renewal
echo "0 12 * * * /usr/bin/certbot renew --quiet --post-hook 'cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem /home/ec2-user/webtrees/certs/webtrees.crt && cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem /home/ec2-user/webtrees/certs/webtrees.key && cd /home/ec2-user/webtrees && docker-compose restart webtrees'" | crontab -

# Start webtrees container
echo "Starting webtrees container..."
docker-compose up -d webtrees

# Disable ImageMagick to prevent thumbnail issues
echo "Disabling ImageMagick..."
docker exec webtrees bash -c "mv /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini /usr/local/etc/php/conf.d/docker-php-ext-imagick.ini.bak" 2>/dev/null || true
docker-compose restart webtrees

# Install Composer and module dependencies
docker exec webtrees bash -c "
    curl -sS https://getcomposer.org/installer | php && 
    mv composer.phar /usr/local/bin/composer && 
    chmod +x /usr/local/bin/composer &&
    cd /var/www/webtrees/modules_v4/webtrees_s3_media &&
    composer install --no-dev --optimize-autoloader
" 2>/dev/null || echo "Composer setup skipped (modules may not be present)"

# Configure S3 Media Module if modules are present
if [ -d "modules_v4/webtrees_s3_media" ]; then
  echo "Configuring S3 Media Module..."
  # Wait a bit for webtrees to fully initialize after restart
  sleep 10
  
  # Set environment variables for the configuration script
  export AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-2")
  export DB_USERNAME DB_PASSWORD DB_NAME S3_BUCKET
  
  # Run the S3 configuration script
  bash /home/ec2-user/webtrees/configure-s3-module.sh
else
  echo "S3 Media Module not found, skipping configuration..."
fi

# Setup monitoring
bash /home/ec2-user/webtrees/cloudwatch-setup.sh

# Copy health check script to correct location
cp /home/ec2-user/webtrees/health-check.sh /usr/local/bin/webtrees-health-check.sh
chmod +x /usr/local/bin/webtrees-health-check.sh

# Get AWS region from AWS CLI config
AWS_REGION=$(aws configure get region 2>/dev/null || echo "us-east-2")

# Create a wrapper script that sets the environment
cat > /usr/local/bin/webtrees-health-wrapper.sh << EOF
#!/bin/bash
export AWS_REGION=$AWS_REGION
export PATH=/usr/local/bin:/usr/bin:/bin
/usr/local/bin/webtrees-health-check.sh
EOF
chmod +x /usr/local/bin/webtrees-health-wrapper.sh

# Schedule health check to run every minute
echo "* * * * * /usr/local/bin/webtrees-health-wrapper.sh > /tmp/health-check.log 2>&1" | crontab -u ec2-user -

echo "Webtrees setup completed successfully!"