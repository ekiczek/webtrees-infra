#!/bin/bash
# Health check script for Docker containers

# Change to webtrees directory where docker-compose.yml is located
cd /home/ec2-user/webtrees

# Get AWS region from environment or default
REGION="${AWS_REGION}"
if [ -z "$REGION" ]; then
  # Try to get from AWS CLI config
  REGION=$(aws configure get region 2>/dev/null)
fi
if [ -z "$REGION" ]; then
  # Default to us-east-2 if not found
  REGION="us-east-2"
fi

# Check if containers are running
WEBTREES_STATUS=$(docker inspect -f '{{.State.Running}}' webtrees 2>/dev/null)
MARIADB_STATUS=$(docker inspect -f '{{.State.Running}}' webtrees_mariadb 2>/dev/null)

# Send custom metrics to CloudWatch
if [ "$WEBTREES_STATUS" = "true" ]; then
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "WebtreesRunning" --value 1 --region $REGION
else
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "WebtreesRunning" --value 0 --region $REGION
fi

if [ "$MARIADB_STATUS" = "true" ]; then
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "MariaDBRunning" --value 1 --region $REGION
else
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "MariaDBRunning" --value 0 --region $REGION
fi

# Check website response
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -k https://localhost/ 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "301" ] || [ "$HTTP_STATUS" = "302" ]; then
  aws cloudwatch put-metric-data --namespace "Webtrees/Application" --metric-name "WebsiteUp" --value 1 --region $REGION
else
  aws cloudwatch put-metric-data --namespace "Webtrees/Application" --metric-name "WebsiteUp" --value 0 --region $REGION
  echo "Website not responding correctly. HTTP Status: $HTTP_STATUS"
fi

# Get container stats
WEBTREES_MEM=$(docker stats webtrees --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//')
MARIADB_MEM=$(docker stats webtrees_mariadb --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//')

if [ ! -z "$WEBTREES_MEM" ]; then
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "WebtreesMemoryPercent" --value $WEBTREES_MEM --region $REGION
fi

if [ ! -z "$MARIADB_MEM" ]; then
  aws cloudwatch put-metric-data --namespace "Webtrees/Docker" --metric-name "MariaDBMemoryPercent" --value $MARIADB_MEM --region $REGION
fi