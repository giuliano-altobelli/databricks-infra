terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.76, <7.0"
    }
  }

  required_version = "~> 1.3"
}
