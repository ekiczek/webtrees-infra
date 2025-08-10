#!/bin/bash
# S3 Module Configuration Script for webtrees

set -e

# Get configuration from environment
DB_USERNAME=${DB_USERNAME:-webtrees}
DB_PASSWORD=${DB_PASSWORD:-webtrees_password}
DB_NAME=${DB_NAME:-webtrees}
S3_BUCKET=${S3_BUCKET}
AWS_REGION=${AWS_REGION}

echo "Configuring webtrees S3 media module..."

# Wait for MariaDB to be ready (if it's not already)
until docker exec webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MariaDB not ready yet, waiting 5 seconds..."
  sleep 5
done

# Create temporary SQL file with substituted variables
cat > /tmp/s3-config.sql << EOF
-- Enable the S3 Media Module
INSERT INTO wt_module (module_name, status, tab_order, menu_order, sidebar_order)
VALUES ('_webtrees_s3_media_', 'enabled', NULL, NULL, NULL)
ON DUPLICATE KEY UPDATE status = 'enabled';

-- Configure S3 module settings
-- Enable S3 storage
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_enabled', '1')
ON DUPLICATE KEY UPDATE setting_value = '1';

-- Set AWS region
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_region', '${AWS_REGION}')
ON DUPLICATE KEY UPDATE setting_value = '${AWS_REGION}';

-- Set S3 bucket name
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_bucket', '${S3_BUCKET}')
ON DUPLICATE KEY UPDATE setting_value = '${S3_BUCKET}';

-- Set media path prefix
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_media_prefix', 'media/')
ON DUPLICATE KEY UPDATE setting_value = 'media/';

-- Leave credentials empty to use IAM role authentication
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_key', '')
ON DUPLICATE KEY UPDATE setting_value = '';

INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_secret', '')
ON DUPLICATE KEY UPDATE setting_value = '';

-- Leave endpoint empty for AWS S3
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_endpoint', '')
ON DUPLICATE KEY UPDATE setting_value = '';

-- Use virtual-hosted style URLs (standard for AWS S3)
INSERT INTO wt_module_setting (module_name, setting_name, setting_value)
VALUES ('_webtrees_s3_media_', 's3_path_style', '0')
ON DUPLICATE KEY UPDATE setting_value = '0';
EOF

# Execute the SQL script
docker exec -i webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD $DB_NAME < /tmp/s3-config.sql

# Clean up temporary file
rm -f /tmp/s3-config.sql

if [ $? -eq 0 ]; then
    echo "S3 module configuration completed successfully!"
    echo "Module enabled with:"
    echo "  - S3 Bucket: ${S3_BUCKET}"
    echo "  - AWS Region: ${AWS_REGION}"
    echo "  - Authentication: IAM Role (no credentials stored)"
else
    echo "Error: Failed to configure S3 module"
    exit 1
fi