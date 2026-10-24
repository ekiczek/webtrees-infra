#!/usr/bin/env bash
# Runs on each attach to the dev container. If the `aws login` session for the
# default profile has expired, start a new login so Terraform and the AWS
# Toolkit have working credentials.

if aws sts get-caller-identity >/dev/null 2>&1; then
  echo "AWS session is valid: $(aws sts get-caller-identity --query Arn --output text)"
  exit 0
fi

# A fresh ~/.aws volume has no config; set a region so `aws login` doesn't prompt.
if [ -z "$(aws configure get region 2>/dev/null)" ]; then
  aws configure set region us-east-2
fi

echo "AWS session expired or missing. Starting 'aws login'..."
echo "Complete the sign-in in your browser (or open the URL below)."
if aws login; then
  echo "AWS login complete. If the AWS Toolkit is stuck on 'Getting credentials',"
  echo "run 'Developer: Reload Window'."
else
  echo "AWS login did not complete. Run 'aws login' in a terminal when ready."
fi

# Never fail container startup over a missed login.
exit 0
