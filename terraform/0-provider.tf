terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region  = "us-east-2"
  
  default_tags {
    tags = var.tags
  }
}

# Although we're standing up most everything in the us-east-2 region,
# there are some things that are required to be in us-east-1. That's
# why this is present.
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  
  default_tags {
    tags = var.tags
  }
}
