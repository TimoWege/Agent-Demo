# Unified Agent Demo

Terraform config that spins up a small AWS demo environment: two Windows
Server 2022 EC2 instances (`timo-1`, `timo-2`), locked down to RDP/SSH from a
single admin IP, with `timo-1` automatically installing a Trend Micro sensor
agent on boot.

## What gets created

- **timo-1**, **timo-2** — Windows Server 2022, `t3.medium` (2 vCPU / 4 GiB
  RAM), default root volume, in the account's default VPC/subnet.
- A **security group** allowing RDP (3389) and SSH (22) only from your
  current public IP (re-detected on every `plan`/`apply`), full outbound
  internet access, nothing else inbound.
- OpenSSH Server enabled on both instances via user-data (password auth,
  `Administrator` account).
- A fresh **RSA key pair**, generated locally and registered with AWS (used
  for RDP password decryption; SSH uses password auth with the same
  password).
- On **timo-1 only**: the sensor agent installer is uploaded to a private S3
  bucket and pulled down + executed via a scoped IAM instance role (see
  [Prerequisites](#prerequisites) — you must supply this file).
- Two local helper scripts, `connect-timo-1.sh` / `connect-timo-2.sh`, that
  open a windowed RDP session with the password fetched live (never written
  to disk).

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

Optional overrides (`terraform.tfvars` or `-var`): `aws_region` (default
`eu-central-1`), `instance_type` (default `t3.medium`), `key_pair_name`
(default `timo-demo-key`).

The apply takes a few minutes: EC2 boot, a ~350 MB S3 download onto timo-1,
then the agent installer registers itself (polled via a registry key, up to
5 minutes) before the hostname is renamed and the instance reboots.

## Using it

```bash
terraform output
```

- `rdp_timo_1` / `rdp_timo_2` — path to the generated connect script, e.g.
  run `./connect-timo-1.sh` to open a windowed RDP session (credentials
  pre-filled, fetched live from AWS each time).
- `ssh_timo_1` / `ssh_timo_2` — `ssh Administrator@<ip>`; you'll be prompted
  for the password.
- `get_admin_password_timo_1` / `_timo_2` — prints the ready-to-run `aws ec2
  get-password-data ...` command if you need the raw password.

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
  the `tools/` installer, or the generated `connect-timo-*.sh` scripts —
  they contain or reference secrets (Terraform state stores the private key
  in plaintext) and are all excluded via `.gitignore`. Each `git clone`
  regenerates these locally via `terraform apply`.
- RDP/SSH passwords are never written to disk or passed as plaintext CLI
  args — the connect scripts fetch the password live and pipe it to
  `sdl-freerdp` over stdin.
- The S3 bucket is private (public access fully blocked) and the IAM role
  on timo-1 can only `s3:GetObject` the one installer key — nothing else.
