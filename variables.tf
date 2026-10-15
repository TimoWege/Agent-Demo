variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1"
}

variable "deployer" {
  description = "Short, unique identifier for you (e.g. first name or initials). Required - this AWS account is shared, and it namespaces the security group, IAM role, key pair, and S3 bucket so your deployment doesn't collide with a colleague's. Lowercase letters, numbers, and hyphens only."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.deployer))
    error_message = "deployer must contain only lowercase letters, numbers, and hyphens (it's used in an S3 bucket name), and can't start or end with a hyphen."
  }
}

variable "instance_type" {
  description = "EC2 instance type (2 vCPU / 4 GiB RAM)"
  type        = string
  default     = "t3.medium"
}

variable "key_pair_name" {
  description = "Name for the generated AWS key pair"
  type        = string
  default     = "demo-key"
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

variable "installer_local_path" {
  description = "Local path to the sensor agent installer executable (not included in this repo - see README). Its filename is reused as the S3 object key and the name it's saved under on the instance."
  type        = string
  default     = "tools/sensor-agent-installer.exe"
}

variable "registration_registry_keys" {
  description = "Windows registry key path(s) to poll after launching the installer, used to detect successful registration. Vendor-specific and deliberately left without a default - set it in a local, uncommitted tfvars file or via TF_VAR_registration_registry_keys."
  type        = list(string)
}

variable "registration_value_name" {
  description = "Registry value name under registration_registry_keys that equals 1 once registration succeeds"
  type        = string
  default     = "default_token_registered"
}
