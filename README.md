# Unified Agent Demo

Terraform config that spins up a small AWS demo environment: two Windows
Server 2022 EC2 instances, locked down to RDP/SSH from a single admin IP,
with the first instance automatically installing a Trend Micro sensor agent
on boot.

Hostnames are **not hardcoded** — every user of this repo sets their own via
the `hostname_1` / `hostname_2` variables (see
[Choosing your own hostnames](#choosing-your-own-hostnames)).

## What gets created

- **Two Windows Server 2022 instances**, `t3.medium` (2 vCPU / 4 GiB RAM),
  default root volume, in the account's default VPC/subnet. Their in-OS
  computer name and the EC2 `Name` tag are set from `var.hostname_1` /
  `var.hostname_2` (defaults: `demo-1` / `demo-2`).
- A **security group** allowing RDP (3389) and SSH (22) only from your
  current public IP (re-detected on every `plan`/`apply`), full outbound
  internet access, nothing else inbound.
- OpenSSH Server enabled on both instances via user-data (password auth,
  `Administrator` account).
- A fresh **RSA key pair**, generated locally and registered with AWS (used
  for RDP password decryption; SSH uses password auth with the same
  password).
- On the **first instance only**: the sensor agent installer is uploaded to
  a private S3 bucket and pulled down + executed via a scoped IAM instance
  role (see [Prerequisites](#prerequisites) — you must supply this file).
- Two local helper scripts, `connect-<hostname_1>.sh` / `connect-<hostname_2>.sh`,
  that open a windowed RDP session with the password fetched live (never
  written to disk).

## Prerequisites

### Tools (macOS, via Homebrew)

```bash
brew install terraform awscli freerdp
```

- **Terraform** >= 1.5
- **AWS CLI v2**, configured with credentials that can create VPC/EC2/IAM/S3
  resources: `aws configure` (or `aws sso login` if your org uses SSO)
- **FreeRDP** (`sdl-freerdp` binary) — used by the generated connect
  scripts to open RDP sessions. No XQuartz/X11 needed, it uses native macOS
  windowing (SDL).

### AWS account

An account/region where you're allowed to create: VPC lookups (uses the
default VPC — must exist), EC2 instances, security groups, key pairs, IAM
roles/instance profiles, and an S3 bucket.

### The sensor agent installer (not included in this repo)

This repo does **not** ship `TMSensorAgent_Windows_x86_64.exe` — it's a
~350 MB proprietary binary, too large for Git and not meant to be
redistributed via a public/shared repo. Before deploying, place it here:

```
tools/TMSensorAgent_Windows_x86_64.exe
```

Without this file, `terraform apply` will fail when it tries to upload it to
S3.

## Setup

```bash
git clone https://github.com/TimoWege/unified-Agent-Demo.git
cd unified-Agent-Demo

# 1. Add the installer (see Prerequisites above)
mkdir -p tools
cp /path/to/TMSensorAgent_Windows_x86_64.exe tools/

# 2. Make sure AWS credentials are set up
aws sts get-caller-identity

# 3. Init & deploy
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

The apply takes a few minutes: EC2 boot, a ~350 MB S3 download onto the
first instance, then the agent installer registers itself (polled via a
registry key, up to 5 minutes) before the hostname is renamed and the
instance reboots.

## Choosing your own hostnames

`hostname_1` and `hostname_2` control the Windows computer name, the EC2
`Name` tag, and the generated connect script's filename for each instance.
Don't hardcode your choice into `terraform.tfvars` if you plan to share this
repo further — use one of these instead, so the defaults stay generic for
the next person:

```bash
# one-off, via CLI flags
terraform apply -var="hostname_1=alice-1" -var="hostname_2=alice-2"

# or persist locally without committing it (gitignored)
cat > terraform.tfvars.local <<EOF
hostname_1 = "alice-1"
hostname_2 = "alice-2"
EOF
terraform apply -var-file=terraform.tfvars.local

# or via environment variables
export TF_VAR_hostname_1="alice-1"
export TF_VAR_hostname_2="alice-2"
terraform apply
```

Other optional overrides: `aws_region` (default `eu-central-1`),
`instance_type` (default `t3.medium`), `key_pair_name` (default
`demo-key`).

## Using it

```bash
terraform output
```

- `rdp_instance_1` / `rdp_instance_2` — path to the generated connect
  script, e.g. run `./connect-<hostname_1>.sh` to open a windowed RDP
  session (credentials pre-filled, fetched live from AWS each time).
- `ssh_instance_1` / `ssh_instance_2` — `ssh Administrator@<ip>`; you'll be
  prompted for the password.
- `get_admin_password_1` / `get_admin_password_2` — prints the ready-to-run
  `aws ec2 get-password-data ...` command if you need the raw password.

If the password command returns empty, AWS hasn't finished generating it yet
(usually ready within a few minutes of first boot) — just retry.

## Updating your admin IP

The security group is re-evaluated against your current public IP on every
`plan`/`apply` — if your IP changed (new network, VPN, etc.), simply re-run:

```bash
terraform apply
```

No manual IP editing required.

## Cleanup

```bash
terraform destroy
```

This tears down both instances, the security group, key pair, IAM
role/instance profile, and the S3 bucket (including the uploaded installer).

## Security notes

- **Never commit** `*.pem`, `terraform.tfstate*`, `tfplan`, `.terraform/`,
  the `tools/` installer, `terraform.tfvars.local`, or the generated
  `connect-*.sh` scripts — they contain or reference secrets (Terraform
  state stores the private key in plaintext) and are all excluded via
  `.gitignore`. Each `git clone` regenerates these locally via
  `terraform apply`.
- RDP/SSH passwords are never written to disk or passed as plaintext CLI
  args — the connect scripts fetch the password live and pipe it to
  `sdl-freerdp` over stdin.
- The S3 bucket is private (public access fully blocked) and the IAM role
  on the first instance can only `s3:GetObject` the one installer key —
  nothing else.
