variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "instance_type" {
  description = "EC2 instance type (2 vCPU / 4 GiB RAM)"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name for the generated AWS key pair"
  type        = string
  default     = "timo-demo-key"
}

variable "hostname_1" {
  description = "Windows computer hostname for the first instance"
  type        = string
  default     = "demo-1"
}

variable "hostname_2" {
  description = "Windows computer hostname for the second instance"
  type        = string
  default     = "demo-2"
}
