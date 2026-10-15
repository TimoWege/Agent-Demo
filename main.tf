terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Admin IP: re-detected on every plan/apply so the security group always ---
# --- matches whatever IP you're currently running Terraform from.          ---

data "http" "my_ip" {
  url = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = "${trimspace(data.http.my_ip.response_body)}/32"

  # Shared-account safety: this AWS account may be used by several people at
  # once, so every resource whose name must be unique within the account is
  # namespaced with var.deployer to avoid collisions between deployments.
  security_group_name    = "demo-sg-${var.deployer}"
  iam_role_name          = "instance1-sensor-agent-s3-read-${var.deployer}"
  key_pair_name          = "${var.key_pair_name}-${var.deployer}"
  installers_bucket_name = "demo-installers-${data.aws_caller_identity.current.account_id}-${var.deployer}"
}

# --- Networking: use the account's default VPC/subnet for this demo ---

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Current Windows Server 2022 AMI ---

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_caller_identity" "current" {}

# --- Installer staging: TMVisionOneAgent_Windows_x86_64.exe is uploaded to a private ---
# --- S3 bucket; the first instance pulls it down via an IAM instance role and     ---
# --- runs it.                                                                    ---

resource "aws_s3_bucket" "installers" {
  bucket        = local.installers_bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "installers" {
  bucket                  = aws_s3_bucket.installers.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "sensor_agent" {
  bucket      = aws_s3_bucket.installers.id
  key         = "TMVisionOneAgent_Windows_x86_64.exe"
  source      = "${path.module}/tools/TMVisionOneAgent_Windows_x86_64.exe"
  source_hash = filemd5("${path.module}/tools/TMVisionOneAgent_Windows_x86_64.exe")
}

resource "aws_iam_role" "instance1_s3_read" {
  name = local.iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "instance1_s3_read" {
  name = "read-sensor-agent-object"
  role = aws_iam_role.instance1_s3_read.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.installers.arn}/${aws_s3_object.sensor_agent.key}"
    }]
  })
}

resource "aws_iam_instance_profile" "instance1_s3_read" {
  name = local.iam_role_name
  role = aws_iam_role.instance1_s3_read.name
}

# --- Key pair (generated locally; private key saved next to this config) ---

resource "tls_private_key" "demo" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.demo.private_key_pem
  filename        = "${path.module}/${local.key_pair_name}.pem"
  file_permission = "0600"
}

resource "aws_key_pair" "demo" {
  key_name   = local.key_pair_name
  public_key = tls_private_key.demo.public_key_openssh
}

# --- Security group: RDP + SSH from my IP only, full egress ---

resource "aws_security_group" "demo" {
  name        = local.security_group_name
  description = "Allow RDP+SSH from a single admin IP, full egress"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "RDP from admin IP"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.my_ip_cidr]
  }

  egress {
    description = "Full outbound internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = local.security_group_name
  }
}

# --- Instances ---

resource "aws_instance" "instance1" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.demo.id]
  key_name                    = aws_key_pair.demo.key_name
  get_password_data           = true
  iam_instance_profile        = aws_iam_instance_profile.instance1_s3_read.name
  user_data_replace_on_change = true

  user_data = <<-EOT
    <powershell>
    ${file("${path.module}/scripts/bootstrap-openssh.ps1")}
    ${templatefile("${path.module}/scripts/install-sensor-agent.ps1.tftpl", {
  bucket_name = aws_s3_bucket.installers.id
  object_key  = aws_s3_object.sensor_agent.key
  region      = var.aws_region
})}
    Rename-Computer -NewName "${var.hostname_1}" -Force -Restart
    </powershell>
  EOT

tags = {
  Name = var.hostname_1
}
}

resource "aws_instance" "instance2" {
  ami                         = data.aws_ami.windows.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.demo.id]
  key_name                    = aws_key_pair.demo.key_name
  get_password_data           = true
  user_data_replace_on_change = true

  user_data = <<-EOT
    <powershell>
    ${file("${path.module}/scripts/bootstrap-openssh.ps1")}
    Rename-Computer -NewName "${var.hostname_2}" -Force -Restart
    </powershell>
  EOT

  tags = {
    Name = var.hostname_2
  }
}

# --- One-command RDP launchers (sdl-freerdp from the "freerdp" Homebrew formula) ---
# Password is fetched live from AWS on every run and piped over stdin to the RDP
# client - it is never written to disk and never appears in `ps`. Window opens
# non-fullscreen (no /f flag).

resource "local_file" "connect_instance1" {
  filename        = "${path.module}/connect-${var.hostname_1}.sh"
  file_permission = "0755"
  content         = <<-EOT
    #!/bin/bash
    set -euo pipefail
    DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
    PASSWORD=$(aws ec2 get-password-data --region ${var.aws_region} --instance-id ${aws_instance.instance1.id} --priv-launch-key "$DIR/${local.key_pair_name}.pem" --query PasswordData --output text)
    if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "None" ]; then
      echo "Password not available yet (AWS needs a few minutes after boot to generate it). Try again shortly." >&2
      exit 1
    fi
    echo "$PASSWORD" | sdl-freerdp /v:${aws_instance.instance1.public_ip} /u:Administrator /from-stdin:force /w:1600 /h:1000 /cert:ignore +clipboard
  EOT
}

resource "local_file" "connect_instance2" {
  filename        = "${path.module}/connect-${var.hostname_2}.sh"
  file_permission = "0755"
  content         = <<-EOT
    #!/bin/bash
    set -euo pipefail
    DIR="$(cd "$(dirname "$${BASH_SOURCE[0]}")" && pwd)"
    PASSWORD=$(aws ec2 get-password-data --region ${var.aws_region} --instance-id ${aws_instance.instance2.id} --priv-launch-key "$DIR/${local.key_pair_name}.pem" --query PasswordData --output text)
    if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "None" ]; then
      echo "Password not available yet (AWS needs a few minutes after boot to generate it). Try again shortly." >&2
      exit 1
    fi
    echo "$PASSWORD" | sdl-freerdp /v:${aws_instance.instance2.public_ip} /u:Administrator /from-stdin:force /w:1600 /h:1000 /cert:ignore +clipboard
  EOT
}
