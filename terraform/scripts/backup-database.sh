#!/bin/bash
# Database backup script for webtrees

set -e

# Change to webtrees directory
cd /home/ec2-user/webtrees

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting webtrees database backup...${NC}"

# Variables - get from environment or use defaults
DB_USER="${DB_USER:-webtrees}"
DB_PASS="${DB_PASS:-webtrees_password}"
DB_NAME="${DB_NAME:-webtrees}"
S3_BUCKET="${S3_BUCKET}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ -z "$S3_BUCKET" ]; then
    echo -e "${RED}Error: S3_BUCKET environment variable not set${NC}"
    exit 1
fi

# Create backup
echo -e "${YELLOW}Creating database dump...${NC}"
docker exec webtrees_mariadb mariadb-dump -u "$DB_USER" --password="$DB_PASS" "$DB_NAME" > /tmp/webtrees-data.sql

if [ $? -eq 0 ]; then
    echo -e "${GREEN}Database dump created successfully${NC}"
    
    # Get file size
    SIZE=$(ls -lh /tmp/webtrees-data.sql | awk '{print $5}')
    echo -e "Backup size: $SIZE"
    
    # Upload to S3 - main backup file
    echo -e "${YELLOW}Uploading main backup to S3...${NC}"
    aws s3 cp /tmp/webtrees-data.sql "s3://$S3_BUCKET/webtrees-data.sql"
    
    # Upload to S3 - timestamped backup
    echo -e "${YELLOW}Creating timestamped backup...${NC}"
    aws s3 cp /tmp/webtrees-data.sql "s3://$S3_BUCKET/backups/webtrees-data-$TIMESTAMP.sql"
    
    # Clean up local file
    rm /tmp/webtrees-data.sql
    
    echo -e "${GREEN}✓ Backup completed successfully!${NC}"
    echo -e "Main backup: s3://$S3_BUCKET/webtrees-data.sql"
    echo -e "Timestamped: s3://$S3_BUCKET/backups/webtrees-data-$TIMESTAMP.sql"
    
    # Optional: List recent backups
    echo -e "\n${YELLOW}Recent backups in S3:${NC}"
    aws s3 ls "s3://$S3_BUCKET/backups/" --recursive | tail -5
else
    echo -e "${RED}✗ Failed to create database dump${NC}"
    exit 1
fi