# Unified Agent Demo

Terraform config that spins up a small AWS demo environment: two Windows
Server 2022 EC2 instances, locked down to RDP/SSH from a single admin IP,
with the first instance automatically installing a Trend Micro sensor agent
on boot.

Hostnames are **not hardcoded** — every user of this repo sets their own via
the `hostname_1` / `hostname_2` variables (see
[Choosing your own hostnames](#choosing-your-own-hostnames)).

⚠️ **This typically targets a shared AWS account.** If you and a colleague
both deploy into the same account, your security group, IAM role, key pair,
and S3 bucket names would collide — so a `deployer` variable is **required**
on every `plan`/`apply`/`destroy` to namespace them per person (see
[Required: set your deployer name](#required-set-your-deployer-name)).

## What gets created

- **Two Windows Server 2022 instances**, `t3.medium` (2 vCPU / 4 GiB RAM),
  default root volume, in the account's default VPC/subnet. Their in-OS
  computer name and the EC2 `Name` tag are set from `var.hostname_1` /
  `var.hostname_2` (defaults: `demo-1` / `demo-2`).
- A **security group** (`demo-sg-<deployer>`) allowing RDP (3389) and SSH
  (22) only from your current public IP (re-detected on every
  `plan`/`apply`), full outbound internet access, nothing else inbound.
- OpenSSH Server enabled on both instances via user-data (password auth,
  `Administrator` account).
- A fresh **RSA key pair** (`<key_pair_name>-<deployer>`), generated
  locally and registered with AWS (used for RDP password decryption; SSH
  uses password auth with the same password).
- On the **first instance only**: the sensor agent installer is uploaded to
  a private S3 bucket (`demo-installers-<account-id>-<deployer>`) and
  pulled down + executed via a scoped IAM instance role
  (`instance1-sensor-agent-s3-read-<deployer>`) — see
  [Prerequisites](#prerequisites), you must supply the installer file.
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
  windowing (SDL). The generated `connect-*.sh` scripts are macOS-only; on
  Windows or Linux just use `terraform output` for the IP/password and
  connect with your platform's own RDP client (e.g. `mstsc.exe` on
  Windows) instead of running the script.

### AWS account

An account/region where you're allowed to create: VPC lookups (uses the
default VPC — must exist), EC2 instances, security groups, key pairs, IAM
roles/instance profiles, and an S3 bucket.

### The sensor agent installer (not included in this repo)

This repo does **not** ship `TMSensorAgent_Windows_x86_64.exe` — it's a
~350 MB proprietary binary, too large for Git and not meant to be
redistributed via a public/shared repo. Get it from
`<TODO: internal distribution location>` and place it here:

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

# 3. Init & deploy (deployer is required - see below)
terraform init
terraform plan -var="deployer=alice" -out=tfplan
terraform apply tfplan
```

The apply takes a few minutes: EC2 boot, a ~350 MB S3 download onto the
first instance, then the agent installer registers itself (polled via a
registry key, up to 5 minutes) before the hostname is renamed and the
instance reboots.

## Required: set your deployer name

This repo is meant to be shared, and typically everyone deploys into the
**same AWS account**. To keep your security group, IAM role, key pair, and
S3 bucket from colliding with a colleague's, the `deployer` variable
namespaces all of them (e.g. `demo-sg-alice` vs. `demo-sg-bob`) — it has no
default, so Terraform refuses to run without it:

```bash
terraform plan -var="deployer=alice"
```

Pick anything short and unique to you (first name, initials — lowercase
letters/numbers/hyphens only). Use the **same value** on every
`plan`/`apply`/`destroy` for your deployment; mixing values makes Terraform
think it should create a second, parallel set of resources. To avoid typing
it every time:

```bash
export TF_VAR_deployer="alice"
```

## Choosing your own hostnames

`hostname_1` and `hostname_2` control the Windows computer name, the EC2
`Name` tag, and the generated connect script's filename for each instance.
Don't hardcode your choice into `terraform.tfvars` if you plan to share this
repo further — use one of these instead, so the defaults stay generic for
the next person:

```bash
# one-off, via CLI flags
terraform apply -var="deployer=alice" -var="hostname_1=alice-1" -var="hostname_2=alice-2"

# or persist locally without committing it (gitignored)
cat > terraform.tfvars.local <<EOF
deployer   = "alice"
hostname_1 = "alice-1"
hostname_2 = "alice-2"
EOF
terraform apply -var-file=terraform.tfvars.local

# or via environment variables
export TF_VAR_deployer="alice"
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
terraform apply -var="deployer=alice"
```

No manual IP editing required (set `TF_VAR_deployer` once and you can just
run `terraform apply`).

## Cleanup

```bash
terraform destroy -var="deployer=alice"
```

Use the same `deployer` value you deployed with (or rely on
`TF_VAR_deployer`/`terraform.tfvars.local` if you set one up). This tears
down both instances, the security group, key pair, IAM role/instance
profile, and the S3 bucket (including the uploaded installer).

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
