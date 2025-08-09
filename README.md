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
* Uses GD instead of ImageMagick
* `webtrees_s3_media` module was created by Claude AI

## Pre-requisites
AWS creds in ~/.aws
Use VSCode Dev Container

Copy terraform.tfvars.template to terraform.tfvars and fill in your values.
Put your migrated SQL dump in the migrated_data directory as webtrees-data.sql.
Put your migrated media folder in the migrated_data directory as media.

First time, run terraform apply.

## Upgrading Docker containers
When upgrading Docker container versions:
1. ******** We need a process to write a webtrees-data.sql dump to S3.
1. Update the tags in your tfvars
1. Run `terraform destroy --target aws_instance.webtrees_instance -auto-approve && terraform apply -auto-approve`
