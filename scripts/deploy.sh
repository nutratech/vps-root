#!/bin/bash
set -e

STAGING_DIR=~/.nginx-staging
CONF_DIR=/etc/nginx/conf.d
echo "Deploying configuration from $STAGING_DIR to $CONF_DIR..."

echo "Detected changes (diff):"
# Diff existing vs staging. "|| true" prevents exit on diff found.
diff -u -r --color=always "$CONF_DIR/" "$STAGING_DIR/" || true
echo ""

echo "Running pre-flight validation on staged config..."
TMP_NGINX_CONF=$(mktemp)

# Create a temporary nginx.conf that points to STAGING_DIR instead of /etc/nginx/conf.d
# We assume the standard include is "/etc/nginx/conf.d/*.conf"
# We strictly replace that string with our staging path.
sed "s|/etc/nginx/conf.d/\*\.conf|$STAGING_DIR/*.conf|g" /etc/nginx/nginx.conf > "$TMP_NGINX_CONF"

if sudo nginx -t -c "$TMP_NGINX_CONF"; then
    echo "✓ Pre-flight validation passed."
    rm "$TMP_NGINX_CONF"
else
    echo "✗ Pre-flight validation FAILED. Aborting."
    rm "$TMP_NGINX_CONF"
    exit 1
fi

# If diff subcommand, exit early.
if [ "$1" = "diff" ]; then exit 0; fi

# Create timestamped backup
BACKUP_DIR=~/nginx_backup_$(date +%s)
echo "Creating backup at $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"

# Backup existing configs if they exist
if sudo ls "$CONF_DIR"/*.conf >/dev/null 2>&1; then
    sudo cp "$CONF_DIR"/*.conf "$BACKUP_DIR/"
fi

echo "Installing new configurations..."
sudo mv "$STAGING_DIR"/*.conf "$CONF_DIR/"
rm -rf "$STAGING_DIR"

echo "Verifying configuration..."
if sudo nginx -t; then
    echo "Configuration is valid. Reloading Nginx..."
    sudo nginx -s reload
    echo "✓ Deployment successful."
else
    echo "✗ Configuration failed validation! Rolling back..."
    sudo cp "$BACKUP_DIR"/*.conf "$CONF_DIR/"
    echo "Rollback complete. Verifying rollback..."
    sudo nginx -t
    exit 1
fi
