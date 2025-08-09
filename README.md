# webtrees-infra

## Overview
This project uses terraform to stand up a Webtrees website on AWS. Design goals include:
* Minimize cost
* Make it easy to migrate media files and database
* Make it easy to upgrade Webtrees and database in the future
* Work seemlessly with a no-cost No-IP.com domain name

## Architecture
The system includes the following AWS infrastructure:
* EC2 for running the No-IP DUC, Webtrees and MariaDB Docker containers
* S3 bucket for storing media files, module for enabling Webtrees to access media files in S3, and a database dump

## Items of note
* Uses GD instead of ImageMagick (I was having problems with ImageMagick and GD seemed more reliable for my use case)
* `webtrees_s3_media` module was created by Claude AI

## Pre-requisites/assumptions
* You have a Webtrees database dump file and a directory of media files available to use.
* Your AWS key and secret are in `~/.aws`.
* You have Docker Desktop installed locally.
* You are using VSCode dev containers (which utilize Docker)

## Installation and Use
1. Open this repo in VSCode, inside of a dev container. A Docker container will be created for you on first run.
1. Copy `terraform.tfvars.template` to `terraform.tfvars` and edit it with your values.
1. Put the SQL dump file in the `migrated_data` directory as `webtrees-data.sql`.
1. Put the migrated media folder in the `migrated_data` directory as `media`.
1. Open a VSCode terminal and run `terraform apply`.

## Upgrading Docker containers
Webtrees and MariaDB will have upgrades over time. Below are the steps for upgrading:
1. Make a database backup using the backup_database_command in the terraform outputs. It's usually something like:
   ```
   ssh -t ec2-user@<YOUR_IP> "docker exec webtrees_mariadb mariadb-dump -u <YOUR_DB_USERNAME> --password='<YOUR_DB_PASSWORD>' webtrees > /tmp/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://<YOUR_S3_BUCKET>/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://<YOUR_S3_BUCKET>/backups/webtrees-data-\$(date +%Y%m%d-%H%M%S).sql && rm /tmp/webtrees-data.sql && echo 'Backup completed: webtrees-data.sql and timestamped copy saved to S3'
   ```
1. Update the Docker container tags in your `terraform.tfvars`.
1. Run `terraform destroy --target aws_instance.webtrees_instance -auto-approve && terraform apply -auto-approve`. This will destroy the current EC2, create a new one, and in the process, restore from the database backup you created above.
