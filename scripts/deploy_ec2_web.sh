#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <ec2-hostname-or-ip> <ssh-key-path> [ssh-user]" >&2
  exit 1
fi

HOST="$1"
KEY_PATH="$2"
SSH_USER="${3:-ubuntu}"
INCENDIO_DOMAINS="${INCENDIO_DOMAINS:-incendiollc.com www.incendiollc.com}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_DIR="$REPO_ROOT/web"

if [[ ! -d "$WEB_DIR" ]]; then
  echo "Cannot find web directory at $WEB_DIR" >&2
  exit 1
fi

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Cannot find SSH key at $KEY_PATH" >&2
  exit 1
fi

SSH_OPTS=(
  -i "$KEY_PATH"
  -o StrictHostKeyChecking=accept-new
)

REMOTE="${SSH_USER}@${HOST}"
REMOTE_RELEASE="/tmp/incendio-web-release.tgz"
REMOTE_ROOT="/var/www/incendio-web"

echo "Packaging web files..."
COPYFILE_DISABLE=1 tar --format ustar -C "$WEB_DIR" -czf - \
  index.html \
  styles.css \
  script.js \
  incendio_logo.png \
  assets \
  | ssh "${SSH_OPTS[@]}" "$REMOTE" "cat > '$REMOTE_RELEASE'"

echo "Installing and configuring Nginx on $HOST..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo INCENDIO_DOMAINS='$INCENDIO_DOMAINS' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_RELEASE="/tmp/incendio-web-release.tgz"
REMOTE_ROOT="/var/www/incendio-web"
NGINX_SITE="/etc/nginx/sites-available/incendio-web"
NGINX_LINK="/etc/nginx/sites-enabled/incendio-web"
DOMAIN_NAMES="${INCENDIO_DOMAINS:-incendiollc.com www.incendiollc.com}"
PRIMARY_DOMAIN="${DOMAIN_NAMES%% *}"
CERT_DIR="/etc/letsencrypt/live/$PRIMARY_DOMAIN"

export DEBIAN_FRONTEND=noninteractive
if ! command -v nginx >/dev/null 2>&1; then
  apt-get update
  apt-get install -y nginx
fi

mkdir -p "$REMOTE_ROOT"
tar -xzf "$REMOTE_RELEASE" -C "$REMOTE_ROOT"
chown -R www-data:www-data "$REMOTE_ROOT"
find "$REMOTE_ROOT" -type d -exec chmod 755 {} \;
find "$REMOTE_ROOT" -type f -exec chmod 644 {} \;

if [[ -f "$CERT_DIR/fullchain.pem" && -f "$CERT_DIR/privkey.pem" ]]; then
cat > "$NGINX_SITE" <<NGINX_CONF
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name $DOMAIN_NAMES;

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name $DOMAIN_NAMES;

  root /var/www/incendio-web;
  index index.html;

  ssl_certificate $CERT_DIR/fullchain.pem;
  ssl_certificate_key $CERT_DIR/privkey.pem;
  include /etc/letsencrypt/options-ssl-nginx.conf;
  ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location ~* \.(?:png|jpg|jpeg|gif|svg|ico|webp|avif)$ {
    add_header Cache-Control "public, max-age=2592000, immutable";
    try_files \$uri =404;
  }

  location ~* \.(?:css|js)$ {
    add_header Cache-Control "public, max-age=300";
    try_files \$uri =404;
  }
}
NGINX_CONF
else
cat > "$NGINX_SITE" <<NGINX_CONF
server {
  listen 80 default_server;
  listen [::]:80 default_server;
  server_name $DOMAIN_NAMES;

  root /var/www/incendio-web;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location ~* \.(?:png|jpg|jpeg|gif|svg|ico|webp|avif)$ {
    add_header Cache-Control "public, max-age=2592000, immutable";
    try_files \$uri =404;
  }

  location ~* \.(?:css|js)$ {
    add_header Cache-Control "public, max-age=300";
    try_files \$uri =404;
  }
}
NGINX_CONF
fi

rm -f /etc/nginx/sites-enabled/default
ln -sfn "$NGINX_SITE" "$NGINX_LINK"

nginx -t
systemctl enable nginx
systemctl reload nginx || systemctl restart nginx

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  ufw allow OpenSSH
  ufw allow "Nginx Full"
fi

rm -f "$REMOTE_RELEASE"
REMOTE_SCRIPT

echo "Done. Test with: http://$HOST/"
