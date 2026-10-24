# webtrees-infra

## Overview
This project uses [terraform](https://developer.hashicorp.com/terraform) to stand up a [Webtrees](https://webtrees.net/) website on [Amazon Web Services](https://aws.amazon.com/) infrastructure. Design goals include:
* Minimize cost
* Make it easy to migrate media files and database
* Make it easy to upgrade Webtrees and database in the future
* Store media on an AWS S3 bucket for easy ongoing management of media files
* Work seemlessly with a no-cost [No-IP.com](https://www.noip.com/) domain name
* Serve Webtrees via https with a free Let's Encrypt certificate

## Architecture
The system includes the following AWS infrastructure:
* EC2 for running the No-IP DUC, Webtrees and MariaDB Docker containers
* S3 bucket for storing media files, module for enabling Webtrees to access media files in S3, supporting scripts, and a database dump
* SES for sending application emails (registration, notifications, password resets) via SMTP
* Monitoring and alarms for EC2 and Docker containers

## Items of note
* Uses GD instead of ImageMagick (which is installed by default). This change was made because I was having problems with ImageMagick and GD seemed more reliable for my use case.
* `webtrees_s3_media` module was created by [Claude AI](https://claude.ai/).

## Email (SES)
Webtrees sends emails for user registration, password resets, and notifications. This project uses AWS SES as the SMTP transport. When the `ses_domain` variable is set in `terraform.tfvars`:
* An SES domain identity is created and verified via Route 53 DNS records (TXT + DKIM)
* A dedicated IAM user with `ses:SendRawEmail` permission is created for SMTP authentication
* SMTP credentials are passed to the EC2 instance and configured in the Webtrees database automatically during setup

Your domain must have an existing Route 53 hosted zone. If your SES account is in sandbox mode, emails can only be sent to verified addresses — request production access through the AWS console to lift this restriction.

## Pre-requisites/assumptions
* You have a Webtrees database dump file and a directory of media files available to use.
* You have an AWS IAM user with console sign-in that can be used with [`aws login`](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html). The dev container keeps its own `~/.aws` in a named Docker volume (`webtrees-infra-aws`), separate from your host's `~/.aws`, so it survives container rebuilds.
* You have Docker Desktop installed locally.
* You are using VSCode dev containers (which utilize Docker)

## Installation and Use
1. Open this repo in VSCode, inside of a dev container. A Docker container will be created for you on first run.
1. Copy `terraform.tfvars.template` to `terraform.tfvars` and edit it with your values.
1. Create a directory named `migrated_data` and add the SQL dump file as `webtrees-data.sql` to that directory.
1. Put the migrated media folder in the `migrated_data` directory as `media`.
1. Open a VSCode terminal and run `terraform apply`.
1. After the `terraform apply` is complete, check the email address provided for the `alert_email` variable and accept the subscription to alerts.

The EC2 will probably need a minute or two to complete setup. Once up, you should be able to browse to the site at your domain name. Additionally, you can monitor the infrastructure health via the AWS dashboard specified in the terraform output `monitoring_dashboard_url`.

## AWS login sessions
`aws login` provides temporary credentials. The CLI refreshes them automatically, but the underlying sign-in session expires after a maximum of about 12 hours, after which you must sign in again. Symptoms of an expired session:
* `aws` commands fail with `Your session has expired. Please reauthenticate using 'aws login'.`
* `terraform` fails to obtain credentials.
* The VSCode AWS Toolkit hangs on "Getting credentials for profile: default".

Each time VSCode attaches to the dev container, `.devcontainer/aws-login.sh` checks the session and runs `aws login` if it has expired (or has never been set up, as on first run with an empty volume). Complete the sign-in in the browser window that opens (or open the URL printed in the startup terminal). You can also run `aws login` manually at any time in a container terminal. Logging in on your host does not affect the container, since the two use separate `~/.aws` directories.

To start over with a clean AWS config, remove the volume with `docker volume rm webtrees-infra-aws` (with the container stopped) and rebuild.

The AWS Toolkit does not retry after failing to get credentials, so after logging in, run **Developer: Reload Window** in VSCode.

## Upgrading Docker containers
Webtrees and MariaDB will have upgrades over time. Below are the steps for upgrading:
1. Make a database backup using the backup_database_command in the terraform outputs. It's usually something like:
   ```
   ssh -t ec2-user@<YOUR_IP> "docker exec webtrees_mariadb mariadb-dump -u <YOUR_DB_USERNAME> --password='<YOUR_DB_PASSWORD>' webtrees > /tmp/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://<YOUR_S3_BUCKET>/webtrees-data.sql && aws s3 cp /tmp/webtrees-data.sql s3://<YOUR_S3_BUCKET>/backups/webtrees-data-\$(date +%Y%m%d-%H%M%S).sql && rm /tmp/webtrees-data.sql && echo 'Backup completed: webtrees-data.sql and timestamped copy saved to S3'
   ```
1. Update the Docker container tags in your `terraform.tfvars`.
1. Run `terraform destroy --target aws_instance.webtrees_instance -auto-approve && terraform apply -auto-approve`. This will destroy the current EC2, create a new one, and in the process, restore from the database backup you created above.
