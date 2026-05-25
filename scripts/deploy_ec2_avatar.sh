#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <ec2-hostname-or-ip> <ssh-key-path> [ssh-user]" >&2
  exit 1
fi

HOST="$1"
KEY_PATH="$2"
SSH_USER="${3:-ubuntu}"
AVATAR_DOMAIN="${AVATAR_DOMAIN:-avatar.incendiollc.com}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AVATAR_DIR="$REPO_ROOT/web/incendio-avatar"

if [[ ! -d "$AVATAR_DIR" ]]; then
  echo "Cannot find avatar website directory at $AVATAR_DIR" >&2
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
REMOTE_RELEASE="/tmp/incendio-avatar-release.tgz"

echo "Packaging avatar website files..."
COPYFILE_DISABLE=1 tar --format ustar -C "$AVATAR_DIR" -czf - . \
  | ssh "${SSH_OPTS[@]}" "$REMOTE" "cat > '$REMOTE_RELEASE'"

echo "Installing and configuring avatar Nginx site on $HOST..."
ssh "${SSH_OPTS[@]}" "$REMOTE" "sudo AVATAR_DOMAIN='$AVATAR_DOMAIN' bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_RELEASE="/tmp/incendio-avatar-release.tgz"
REMOTE_ROOT="/var/www/incendio-avatar"
NGINX_SITE="/etc/nginx/sites-available/incendio-avatar"
NGINX_LINK="/etc/nginx/sites-enabled/incendio-avatar"
DOMAIN_NAME="${AVATAR_DOMAIN:-avatar.incendiollc.com}"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN_NAME"

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
  listen 80;
  listen [::]:80;
  server_name $DOMAIN_NAME;

  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  listen [::]:443 ssl;
  server_name $DOMAIN_NAME;

  root /var/www/incendio-avatar;
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

  location ~* \.(?:css|js|xml|txt)$ {
    add_header Cache-Control "public, max-age=300";
    try_files \$uri =404;
  }
}
NGINX_CONF
else
cat > "$NGINX_SITE" <<NGINX_CONF
server {
  listen 80;
  listen [::]:80;
  server_name $DOMAIN_NAME;

  root /var/www/incendio-avatar;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }

  location ~* \.(?:png|jpg|jpeg|gif|svg|ico|webp|avif)$ {
    add_header Cache-Control "public, max-age=2592000, immutable";
    try_files \$uri =404;
  }

  location ~* \.(?:css|js|xml|txt)$ {
    add_header Cache-Control "public, max-age=300";
    try_files \$uri =404;
  }
}
NGINX_CONF
fi

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

echo "Done. Test with: http://$AVATAR_DOMAIN/"
