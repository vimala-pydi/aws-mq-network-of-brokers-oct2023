variable "env_name" {
  description = "the name of your stack, e.g. \"demo\""
  default     = "demo"
}

variable "region" {
  description = "the AWS region in which primary resources are created"
  default     = "us-gov-east-1"
}

variable "dr_region" {
  description = "the AWS region in which secondary resources are created"
  default     = "us-gov-west-1"
}

variable "user" {
  description = "Admin user for the brokers"
  default     = "exampleuser"
}

variable "password" {
  description = "Admin user password"
  default     = "examplepassword"
}

variable "cidr_block" {
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}
