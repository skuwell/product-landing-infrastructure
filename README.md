# product-landing-infrastructure

Terraform infrastructure for deploying **ProfitLaunch** ([skuwell/product-landing-app](https://github.com/skuwell/product-landing-app)) on Google Cloud Platform.

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Repository Structure](#repository-structure)
3. [Modules](#modules)
4. [Prerequisites](#prerequisites)
5. [First-Time Setup](#first-time-setup)
6. [Deploying](#deploying)
7. [What the Startup Script Does](#what-the-startup-script-does)
8. [Secrets Management](#secrets-management)
9. [TLS / HTTPS](#tls--https)
10. [Database Backups](#database-backups)
11. [Updating the Application](#updating-the-application)
12. [Destroying Infrastructure](#destroying-infrastructure)
13. [Cost Estimate](#cost-estimate)

---

## Architecture Overview

```
Internet
   │  443 / 80
   ▼
Static External IP
   │
   ▼
GCP VM (e2-standard-2, Ubuntu 22.04)
   │
   ├── nginx (host) ─── TLS termination (Let's Encrypt)
   │       │ proxy_pass → localhost:3000
   │       ▼
   └── Docker Compose (7 containers)
           ├── frontend       :3000
           ├── api-gateway    :8080
           ├── auth-service   :8001  ◄── JWT_PRIVATE_KEY (signs RS256 tokens)
           ├── product-service:8002  ◄── JWT_PUBLIC_KEY  (verifies tokens)
           ├── cogs-service   :8003  ◄── JWT_PUBLIC_KEY  (verifies tokens)
           └── redis          :6379
           (postgres container DISABLED — uses Cloud SQL below)

Cloud SQL Auth Proxy (host daemon, port 5432)
   │
   ▼
Cloud SQL PostgreSQL 16
   ├── Automated backups (30-day retention)
   └── PITR (Point-in-Time Recovery)

GCS Buckets
   ├── uploads/                  (app file uploads)
   ├── pgdump/YYYYMMDD.sql.gz    (daily pg_dump cron backup)
   └── terraform-state/          (Terraform remote state)

Secret Manager
   ├── jwt-private-key-<env>
   ├── jwt-public-key-<env>
   ├── db-password-<env>
   └── app-secret-key-<env>
```

---

## Repository Structure

```
product-landing-infrastructure/
├── main.tf                    # Root config — wires all modules together
├── variables.tf               # All input variables with defaults
├── outputs.tf                 # Deployment summary, IPs, SSH command
├── backend.tf                 # GCS remote state backend
├── startup-script.sh          # VM bootstrap — installs Docker, deploys app
├── terraform.tfvars.example   # Copy → terraform.tfvars and fill in values
└── modules/
    ├── networking/             # VPC, subnet, Cloud NAT, firewall rules
    ├── compute/                # VM instance, startup script, security hardening
    ├── database/               # Cloud SQL PostgreSQL with backups
    ├── storage/                # GCS buckets (uploads, backups, tf-state)
    ├── security/               # Service accounts, Secret Manager secrets
    └── apis/                   # GCP API enablement
```

---

## Modules

### `modules/networking`

Creates:
- Custom VPC network
- Regional subnet (`10.1.0.0/24` by default)
- Cloud NAT (outbound internet for containers without a public IP)
- Firewall rules: SSH (22), HTTP (80), HTTPS (443)

| Input | Default | Description |
|---|---|---|
| `vpc_name` | `product-landing-vpc` | VPC network name |
| `subnet_cidr` | `10.1.0.0/24` | Subnet CIDR |
| `enable_cloud_nat` | `true` | Enable outbound NAT |
| `allowed_ssh_cidr_ranges` | `["0.0.0.0/0"]` | Restrict for production |

### `modules/compute`

Creates:
- VM instance (`e2-standard-2`, Ubuntu 22.04 LTS)
- External static IP
- `enable_security_hardening` flag: installs UFW, fail2ban, and unattended-upgrades via a secondary startup script

| Input | Default | Description |
|---|---|---|
| `machine_type` | `e2-standard-2` | GCP machine type |
| `disk_size_gb` | `40` | Boot disk size |
| `enable_security_hardening` | `true` | UFW + fail2ban + auto-updates |

### `modules/database`

Creates:
- Cloud SQL PostgreSQL 16 instance
- Automated daily backups with 30-day point-in-time recovery (PITR)
- `require_ssl = true`
- Password stored in Secret Manager

| Input | Default | Description |
|---|---|---|
| `tier` | `db-g1-small` | Cloud SQL machine tier |
| `backup_enabled` | `true` | Automated backups |
| `ha_enabled` | `false` | High-availability failover replica |

### `modules/storage`

Creates three GCS buckets:
- `<prefix>-uploads` — application file uploads
- `<prefix>-backups` — daily `pg_dump` files (30-day lifecycle delete)
- `<prefix>-terraform-state` — Terraform remote state

### `modules/security`

Creates:
- Application service account (`<app>-sa-<env>`)
- Terraform service account
- Secret Manager secrets: `app-secret-key-<env>`
- Grants `secretmanager.secretAccessor` to the app service account

The root `main.tf` adds additional secrets specific to product-landing: `jwt-private-key-<env>`, `jwt-public-key-<env>`, `db-password-<env>`.

---

## Prerequisites

1. **Terraform** ≥ 1.6.0 — [install](https://developer.hashicorp.com/terraform/install)
2. **Google Cloud SDK** (`gcloud`) — [install](https://cloud.google.com/sdk/docs/install)
3. A GCP project with billing enabled
4. `gcloud auth application-default login` completed
5. An RSA-2048 key pair (see [Secrets Management](#secrets-management))

---

## First-Time Setup

### 1. Create the Terraform state bucket

Before running `terraform init` you need the GCS state bucket to exist:

```bash
gcloud storage buckets create gs://product-landing-terraform-state \
    --project=YOUR_PROJECT_ID \
    --location=US \
    --uniform-bucket-level-access
```

### 2. Configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — required fields:

```hcl
project_id      = "your-gcp-project-id"
domain          = "your-domain.com"        # "" to skip Let's Encrypt
certbot_email   = "you@example.com"

jwt_private_key_pem = <<-EOT
-----BEGIN RSA PRIVATE KEY-----
<paste your private key here>
-----END RSA PRIVATE KEY-----
EOT

jwt_public_key_pem = <<-EOT
-----BEGIN PUBLIC KEY-----
<paste your public key here>
-----END PUBLIC KEY-----
EOT
```

> **Security**: `terraform.tfvars` is in `.gitignore`. Never commit it.

### 3. Grant Terraform the required IAM roles

```bash
PROJECT=your-gcp-project-id
SA=terraform@${PROJECT}.iam.gserviceaccount.com  # or use your own account

for role in \
  roles/compute.admin \
  roles/iam.serviceAccountAdmin \
  roles/storage.admin \
  roles/cloudsql.admin \
  roles/secretmanager.admin \
  roles/resourcemanager.projectIamAdmin; do
  gcloud projects add-iam-policy-binding $PROJECT \
    --member="user:$(gcloud config get-value account)" \
    --role="$role"
done
```

---

## Deploying

```bash
# Initialise (downloads providers, configures GCS backend)
terraform init

# Preview changes
terraform plan

# Apply
terraform apply
```

Terraform will output the VM's external IP and an SSH command when complete.

### Post-apply

1. **DNS**: Point your domain's A-record to the VM external IP shown in the output.
2. **Wait**: The startup script takes ~5 minutes. Monitor it:
   ```bash
   gcloud compute ssh product-landing-vm --zone=us-central1-a \
     --command "sudo journalctl -u google-startup-scripts -f"
   ```
3. **Visit**: `https://your-domain.com` (or the IP if no domain).

---

## What the Startup Script Does

`startup-script.sh` runs on first boot (and on VM restart) via `google-startup-scripts`:

1. Installs Docker CE, docker compose plugin, nginx, certbot, Cloud SQL Auth Proxy, and Google Cloud Ops Agent
2. Starts the **Cloud SQL Auth Proxy** as a systemd service, exposing Cloud SQL at `127.0.0.1:5432`
3. Creates the database and user if they don't exist
4. Fetches all secrets from **Secret Manager** and writes `/opt/product-landing/.env`
5. Clones `skuwell/product-landing-app` (or pulls latest on subsequent boots)
6. Runs `docker compose up -d --build --scale postgres=0` (Cloud SQL replaces the postgres container)
7. Runs Alembic migrations on all three services
8. Configures host **nginx** as a TLS-terminating reverse proxy to the frontend container
9. Runs **certbot** to obtain a Let's Encrypt certificate (if `domain` and `certbot_email` are set)
10. Sets up a nightly **pg_dump → GCS** cron job and a certbot renewal cron

Logs: `/var/log/startup-script.log`

---

## Secrets Management

All secrets are stored in **GCP Secret Manager** and pulled at VM boot. Nothing sensitive is in the Terraform state or git history.

| Secret name | Content |
|---|---|
| `jwt-private-key-<env>` | RSA-2048 private key PEM |
| `jwt-public-key-<env>` | RSA-2048 public key PEM |
| `db-password-<env>` | Cloud SQL database password (auto-generated) |
| `app-secret-key-<env>` | Random 64-char application secret key |

### Rotating the JWT key pair

```bash
# 1. Generate new keys
openssl genrsa -out new_private.pem 2048
openssl rsa -in new_private.pem -pubout -out new_public.pem

# 2. Update secrets (new version — old version remains accessible temporarily)
gcloud secrets versions add jwt-private-key-product-landing \
    --data-file=new_private.pem --project=YOUR_PROJECT_ID
gcloud secrets versions add jwt-public-key-product-landing \
    --data-file=new_public.pem --project=YOUR_PROJECT_ID

# 3. Restart the app to pick up new keys
gcloud compute ssh product-landing-vm --zone=us-central1-a \
    --command "cd /opt/product-landing && sudo docker compose restart"
```

Note: existing tokens signed with the old key will be invalid after rotation. Users will need to log in again.

---

## TLS / HTTPS

TLS is terminated by **nginx on the host** (not inside Docker). nginx proxies decrypted traffic to the frontend container at `localhost:3000`.

- Certificate obtained by **certbot** (Let's Encrypt ACME webroot challenge) on first boot
- Auto-renewed by a cron job: `0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'`
- TLS 1.2 + 1.3 only; HSTS header set (`max-age=63072000; includeSubDomains; preload`)

If `domain` is left empty in `terraform.tfvars`, nginx runs in plain HTTP mode (useful for testing with just an IP address).

---

## Database Backups

Two complementary backup strategies:

### Cloud SQL automated backups (primary)

- Daily automated backups retained for **30 days**
- **Point-in-Time Recovery (PITR)** enabled — restore to any second within the retention window
- Managed entirely by Cloud SQL; no manual intervention required

### Daily pg_dump to GCS (secondary safety net)

A cron job runs at 02:30 daily:

```bash
pg_dump -h 127.0.0.1 -U app_user productlanding | gzip \
    > /tmp/productlanding_YYYYMMDD.sql.gz
gsutil cp /tmp/... gs://<backups-bucket>/pgdump/
```

GCS bucket has a **30-day lifecycle delete** policy. Logs: `/var/log/pg-backup.log`

### Restoring from pg_dump backup

```bash
# Download the backup
gsutil cp gs://<backups-bucket>/pgdump/20260325_023000.sql.gz /tmp/backup.sql.gz

# Restore
gunzip -c /tmp/backup.sql.gz | psql -h 127.0.0.1 -U app_user productlanding
```

---

## Updating the Application

The startup script pulls the latest code on every VM restart. To deploy a new version without restarting the VM:

```bash
gcloud compute ssh product-landing-vm --zone=us-central1-a -- bash -s <<'EOF'
cd /opt/product-landing
git pull origin main
docker compose up -d --build --remove-orphans --scale postgres=0
docker compose exec -T auth-service    alembic upgrade head
docker compose exec -T product-service alembic upgrade head
docker compose exec -T cogs-service    alembic upgrade head
EOF
```

---

## Destroying Infrastructure

```bash
terraform destroy
```

> **Warning**: This will delete the VM, Cloud SQL instance (and all data), and GCS buckets. Make sure you have backups before destroying.

---

## Cost Estimate

Approximate monthly cost in `us-central1` (March 2026):

| Resource | Type | Est. cost/month |
|---|---|---|
| VM | `e2-standard-2` | ~$49 |
| Cloud SQL | `db-g1-small`, 20 GB | ~$25 |
| GCS | 3 buckets, ~10 GB storage | ~$0.25 |
| Static IP | (attached to running VM) | ~$0 |
| Cloud NAT | low traffic | ~$1 |
| Secret Manager | 4 secrets | ~$0.24 |
| **Total** | | **~$75/month** |

To reduce cost during low-traffic periods, shut the VM down (data is safe in Cloud SQL):
```bash
gcloud compute instances stop product-landing-vm --zone=us-central1-a
```
