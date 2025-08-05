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

# Create directory for webtrees
mkdir -p /home/ec2-user/webtrees
chown ec2-user:ec2-user /home/ec2-user/webtrees

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
version: '3.8'

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
    volumes:
      - ./config.ini.php:/var/www/webtrees/data/config.ini.php
      - webtrees_data:/var/www/webtrees/data
      - webtrees_media:/var/www/webtrees/media
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

# Start the containers
cd /home/ec2-user/webtrees
docker-compose up -d

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