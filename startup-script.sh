#!/bin/bash
# =============================================================================
# startup-script.sh — Product Landing App GCP VM bootstrap
#
# Executed once on first boot (and on every restart via google-startup-scripts).
# Terraform templatefile() injects the variables in ${...} notation.
#
# What this script does:
#   1. Install Docker, docker compose plugin, git, nginx, certbot, Cloud SQL Proxy
#   2. Install Google Cloud Ops Agent for logging/monitoring
#   3. Fetch secrets from Secret Manager (.env file)
#   4. Clone product-landing-app and start containers
#   5. Configure host nginx as TLS terminator (Let's Encrypt via certbot)
#   6. Set up daily pg_dump → GCS backup cron job
# =============================================================================
set -euo pipefail
exec > >(tee -a /var/log/startup-script.log) 2>&1

echo "[startup] =============================="
echo "[startup] Product Landing bootstrap - $(date)"
echo "[startup] =============================="

PROJECT_ID="${project_id}"
ENVIRONMENT="${environment}"
APP_NAME="${app_name}"
APP_DIR="/opt/$APP_NAME"
REPO_URL="${app_repo_url}"
REPO_BRANCH="${app_repo_branch}"
DOMAIN="${domain}"
CERTBOT_EMAIL="${certbot_email}"
DB_CONNECTION_NAME="${db_connection_name}"
DB_NAME="${db_name}"
DB_USER="${db_user}"
BACKUPS_BUCKET="${backups_bucket}"
ALLOWED_ORIGINS="${allowed_origins}"

# ---------------------------------------------------------------------------
# 1. System packages
# ---------------------------------------------------------------------------
echo "[startup] Installing system packages..."
apt-get update -qq
apt-get install -y -qq \
    ca-certificates curl gnupg lsb-release \
    git nginx certbot python3-certbot-nginx \
    postgresql-client jq

# Docker CE
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
fi

# Cloud SQL Auth Proxy v2
if ! command -v cloud-sql-proxy &>/dev/null; then
    curl -fSL https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.10.0/cloud-sql-proxy.linux.amd64 \
        -o /usr/local/bin/cloud-sql-proxy
    chmod +x /usr/local/bin/cloud-sql-proxy
fi

# ---------------------------------------------------------------------------
# 2. Google Cloud Ops Agent
# ---------------------------------------------------------------------------
if ! systemctl is-active --quiet google-cloud-ops-agent; then
    curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
    bash add-google-cloud-ops-agent-repo.sh --also-install --version=latest
    systemctl enable --now google-cloud-ops-agent
fi

# ---------------------------------------------------------------------------
# 3. Fetch secrets from Secret Manager
# ---------------------------------------------------------------------------
echo "[startup] Fetching secrets from Secret Manager..."

fetch_secret() {
    gcloud secrets versions access latest \
        --secret="$1" --project="$PROJECT_ID" 2>/dev/null || echo ""
}

JWT_PRIVATE_KEY=$(fetch_secret "jwt-private-key-$ENVIRONMENT")
JWT_PUBLIC_KEY=$(fetch_secret "jwt-public-key-$ENVIRONMENT")
DB_PASSWORD=$(fetch_secret "db-password-$ENVIRONMENT")
APP_SECRET_KEY=$(fetch_secret "app-secret-key-$ENVIRONMENT")

if [[ -z "$JWT_PRIVATE_KEY" || -z "$JWT_PUBLIC_KEY" || -z "$DB_PASSWORD" ]]; then
    echo "[startup] ERROR: Required secrets not found in Secret Manager. Aborting."
    exit 1
fi

# Escape PEM keys to single-line env format (replace real \n with literal \n)
JWT_PRIVATE_KEY_ENV=$(echo "$JWT_PRIVATE_KEY" | awk '{printf "%s\\n", $0}' | tr -d '\n')
JWT_PUBLIC_KEY_ENV=$(echo "$JWT_PUBLIC_KEY" | awk '{printf "%s\\n", $0}' | tr -d '\n')

# ---------------------------------------------------------------------------
# 4. GitHub Actions self-hosted runner
# ---------------------------------------------------------------------------
echo "[startup] Configuring GitHub Actions self-hosted runner..."

RUNNER_VERSION="2.323.0"
RUNNER_USER="gh-runner"
RUNNER_DIR="/opt/actions-runner"

# Dedicated non-root user; must be in the docker group to run docker commands
if ! id "$RUNNER_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$RUNNER_USER"
fi
usermod -aG docker "$RUNNER_USER"

# Download and unpack the runner binary (idempotent)
if [[ ! -f "$RUNNER_DIR/run.sh" ]]; then
    mkdir -p "$RUNNER_DIR"
    curl -fsSL \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
        -o /tmp/actions-runner.tar.gz
    tar -xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
    rm /tmp/actions-runner.tar.gz
    chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"
fi

GITHUB_PAT=$(fetch_secret "github-runner-pat-$ENVIRONMENT")

if [[ -z "$GITHUB_PAT" ]]; then
    echo "[startup] WARNING: github-runner-pat-$ENVIRONMENT not found in Secret Manager — skipping runner registration."
else
    # Exchange the PAT for a short-lived registration token via the GitHub API
    REG_TOKEN=$(curl -fsSL \
        -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GITHUB_PAT" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/repos/${github_repo}/actions/runners/registration-token" \
        | jq -r '.token // empty')

    if [[ -z "$REG_TOKEN" ]]; then
        echo "[startup] WARNING: Could not obtain runner registration token — verify PAT has 'repo' scope."
    else
        RUNNER_NAME="$(hostname)"
        # --replace removes any stale runner registered under the same name
        su - "$RUNNER_USER" -c \
            "\"$RUNNER_DIR/config.sh\" \
                --url \"https://github.com/${github_repo}\" \
                --token \"$REG_TOKEN\" \
                --name \"$RUNNER_NAME\" \
                --labels \"${github_runner_labels}\" \
                --work \"$RUNNER_DIR/_work\" \
                --unattended \
                --replace"

        # Install runner as a systemd service and start it
        pushd "$RUNNER_DIR" >/dev/null
        ./svc.sh install "$RUNNER_USER" 2>&1 || true
        ./svc.sh start 2>&1 || true
        popd >/dev/null

        echo "[startup] GitHub Actions runner registered: name=$RUNNER_NAME labels=${github_runner_labels}"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Cloud SQL Auth Proxy — expose Cloud SQL as localhost:5432
# ---------------------------------------------------------------------------
cat > /etc/systemd/system/cloud-sql-proxy.service <<EOF
[Unit]
Description=Cloud SQL Auth Proxy
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/cloud-sql-proxy \
    --address 0.0.0.0 \
    --port 5432 \
    $DB_CONNECTION_NAME
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloud-sql-proxy

# Give the proxy a moment to be ready
sleep 5

# Create database and user (idempotent)
echo "[startup] Ensuring database and user exist..."
PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U postgres -tc \
    "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER'" | grep -q 1 || \
    PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U postgres \
        -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';"

PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U postgres -tc \
    "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -q 1 || \
    PGPASSWORD="$DB_PASSWORD" psql -h 127.0.0.1 -U postgres \
        -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

# ---------------------------------------------------------------------------
# 6. Clone / update application
# ---------------------------------------------------------------------------
echo "[startup] Deploying application from $REPO_URL ($REPO_BRANCH)..."

if [[ -d "$APP_DIR/.git" ]]; then
    git -C "$APP_DIR" fetch origin "$REPO_BRANCH"
    git -C "$APP_DIR" reset --hard "origin/$REPO_BRANCH"
else
    git clone --branch "$REPO_BRANCH" --depth 1 "$REPO_URL" "$APP_DIR"
fi

# ---------------------------------------------------------------------------
# 7. Write .env file (read by docker compose)
# ---------------------------------------------------------------------------
cat > "$APP_DIR/.env" <<EOF
# Generated by GCP startup script — do not edit manually
POSTGRES_USER=$DB_USER
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_DB=$DB_NAME
DB_HOST=host-gateway
JWT_PRIVATE_KEY=$JWT_PRIVATE_KEY_ENV
JWT_PUBLIC_KEY=$JWT_PUBLIC_KEY_ENV
ALGORITHM=RS256
SECURE_COOKIES=true
ALLOWED_ORIGINS=$${ALLOWED_ORIGINS:-$ALLOWED_ORIGINS}
LOG_LEVEL=INFO
# Vertex AI Gemini — enables image-based HTS code lookup.
# ADC on GCP uses the VM's service account automatically; no API key needed.
GOOGLE_CLOUD_PROJECT=$PROJECT_ID
GOOGLE_CLOUD_LOCATION=${google_cloud_location}
EOF
chmod 600 "$APP_DIR/.env"

# ---------------------------------------------------------------------------
# 8. Start Docker Compose (skip postgres container — using Cloud SQL)
# ---------------------------------------------------------------------------
echo "[startup] Starting containers..."
cd "$APP_DIR"

# Use the host network so containers can reach Cloud SQL via 127.0.0.1:5432
docker compose pull --quiet || true
docker compose up -d --build --remove-orphans --scale postgres=0

# ---------------------------------------------------------------------------
# 9. Run Alembic migrations
# ---------------------------------------------------------------------------
echo "[startup] Running database migrations..."
sleep 10  # wait for services to be healthy
docker compose exec -T auth-service alembic upgrade head || true
docker compose exec -T product-service alembic upgrade head || true
docker compose exec -T cogs-service alembic upgrade head || true

# ---------------------------------------------------------------------------
# 10. Host nginx — TLS termination → docker frontend :3000
# ---------------------------------------------------------------------------
echo "[startup] Configuring nginx..."

cat > /etc/nginx/sites-available/product-landing <<'NGINX'
# HTTP → redirect to HTTPS (will be replaced by certbot)
server {
    listen 80;
    server_name _;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS — proxy to frontend container
server {
    listen 443 ssl http2;
    server_name _;

    ssl_certificate     /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/product-landing /etc/nginx/sites-enabled/product-landing
rm -f /etc/nginx/sites-enabled/default

# ---------------------------------------------------------------------------
# 11. Certbot — obtain Let's Encrypt certificate
# ---------------------------------------------------------------------------
mkdir -p /var/www/certbot

if [[ -n "$DOMAIN" && -n "$CERTBOT_EMAIL" ]]; then
    # Update nginx config with real domain
    sed -i "s/server_name _;/server_name $DOMAIN;/g" /etc/nginx/sites-available/product-landing
    sed -i "s|/etc/letsencrypt/live/DOMAIN/|/etc/letsencrypt/live/$DOMAIN/|g" /etc/nginx/sites-available/product-landing

    # Start nginx with HTTP-only first (cert doesn't exist yet)
    # Comment out the HTTPS block temporarily for the initial HTTP challenge
    nginx -t && systemctl reload nginx || systemctl start nginx

    certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --non-interactive \
        --agree-tos \
        --email "$CERTBOT_EMAIL" \
        -d "$DOMAIN" || true

    # Renewal cron
    echo "0 3 * * * root certbot renew --quiet --post-hook 'systemctl reload nginx'" \
        > /etc/cron.d/certbot-renew
else
    echo "[startup] WARNING: DOMAIN or CERTBOT_EMAIL not set — skipping TLS setup."
    # Fall back to plain HTTP proxy
    cat > /etc/nginx/sites-available/product-landing <<'NGINX_HTTP'
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX_HTTP
fi

nginx -t && (systemctl reload nginx 2>/dev/null || systemctl start nginx)

# ---------------------------------------------------------------------------
# 11. Daily pg_dump → GCS backup cron
# ---------------------------------------------------------------------------
cat > /usr/local/bin/pg-backup.sh <<PGSCRIPT
#!/bin/bash
# Daily PostgreSQL backup to GCS
set -euo pipefail
DATE=\$(date +%Y%m%d_%H%M%S)
DUMP=/tmp/productlanding_\$DATE.sql.gz
DB_PASSWORD=\$(gcloud secrets versions access latest --secret=db-password-$ENVIRONMENT --project=$PROJECT_ID)
PGPASSWORD="\$DB_PASSWORD" pg_dump -h 127.0.0.1 -U $DB_USER $DB_NAME | gzip > "\$DUMP"
gsutil cp "\$DUMP" "gs://$BACKUPS_BUCKET/pgdump/\$DATE.sql.gz"
rm -f "\$DUMP"
echo "Backup uploaded: gs://$BACKUPS_BUCKET/pgdump/\$DATE.sql.gz"
PGSCRIPT
chmod +x /usr/local/bin/pg-backup.sh

echo "30 2 * * * root /usr/local/bin/pg-backup.sh >> /var/log/pg-backup.log 2>&1" \
    > /etc/cron.d/pg-backup

echo "[startup] =============================="
echo "[startup] Bootstrap complete - $(date)"
echo "[startup] Application: http://$(curl -s http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip -H 'Metadata-Flavor: Google')"
echo "[startup] =============================="
