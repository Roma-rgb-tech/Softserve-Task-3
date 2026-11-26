terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    keycloak = {
      source  = "keycloak/keycloak"
      version = "~> 5.10"
    }
  }

  backend "s3" {
    bucket       = "roma-tfstate-softserve-task1"
    key          = "task3/keycloak/terraform.tfstate"
    region       = "eu-north-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket = "roma-tfstate-softserve-task1"
    key    = "task3/terraform.tfstate"
    region = "eu-north-1"
  }
}

data "aws_ssm_parameter" "keycloak_admin_password" {
  name = data.terraform_remote_state.infra.outputs.keycloak_admin_password_parameter
}

provider "keycloak" {
  client_id = "admin-cli"
  username  = "admin"
  password  = data.aws_ssm_parameter.keycloak_admin_password.value
  url       = data.terraform_remote_state.infra.outputs.keycloak_url
}
