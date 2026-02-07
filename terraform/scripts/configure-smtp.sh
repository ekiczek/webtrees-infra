#!/bin/bash
# SMTP Configuration Script for webtrees (SES)

set -e

# Get configuration from environment
DB_USERNAME=${DB_USERNAME:-webtrees}
DB_PASSWORD=${DB_PASSWORD:-webtrees_password}
DB_NAME=${DB_NAME:-webtrees}
SMTP_HOST=${SMTP_HOST}
SMTP_PORT=${SMTP_PORT:-587}
SMTP_USER=${SMTP_USER}
SMTP_PASS=${SMTP_PASS}
SMTP_FROM=${SMTP_FROM}
SMTP_HELO=${SMTP_HELO}

echo "Configuring webtrees SMTP settings..."

# Wait for MariaDB to be ready (if it's not already)
until docker exec webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD -e "SELECT 1;" > /dev/null 2>&1; do
  echo "MariaDB not ready yet, waiting 5 seconds..."
  sleep 5
done

# Create temporary SQL file with SMTP settings
cat > /tmp/smtp-config.sql << EOF
-- Configure SMTP to use external server (SES)
INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_ACTIVE', 'external')
ON DUPLICATE KEY UPDATE setting_value = 'external';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_HOST', '${SMTP_HOST}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_HOST}';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_PORT', '${SMTP_PORT}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_PORT}';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_SSL', 'tls')
ON DUPLICATE KEY UPDATE setting_value = 'tls';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_AUTH', '1')
ON DUPLICATE KEY UPDATE setting_value = '1';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_AUTH_USER', '${SMTP_USER}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_USER}';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_AUTH_PASS', '${SMTP_PASS}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_PASS}';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_FROM_NAME', '${SMTP_FROM}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_FROM}';

INSERT INTO wt_site_setting (setting_name, setting_value)
VALUES ('SMTP_HELO', '${SMTP_HELO}')
ON DUPLICATE KEY UPDATE setting_value = '${SMTP_HELO}';
EOF

# Execute the SQL script
docker exec -i webtrees_mariadb /usr/bin/mariadb -u $DB_USERNAME --password=$DB_PASSWORD $DB_NAME < /tmp/smtp-config.sql

# Clean up temporary file
rm -f /tmp/smtp-config.sql

if [ $? -eq 0 ]; then
    echo "SMTP configuration completed successfully!"
    echo "Settings applied:"
    echo "  - SMTP Host: ${SMTP_HOST}"
    echo "  - SMTP Port: ${SMTP_PORT}"
    echo "  - SMTP SSL: tls"
    echo "  - SMTP Auth: enabled"
    echo "  - SMTP From: ${SMTP_FROM}"
    echo "  - SMTP HELO: ${SMTP_HELO}"
else
    echo "Error: Failed to configure SMTP settings"
    exit 1
fi
