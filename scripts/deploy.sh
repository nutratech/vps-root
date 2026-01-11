#!/bin/bash
set -e

# Staging directory expected to be populated by the caller (Makefile)
# We default to the directory containing this script.
STAGING_DIR=$(dirname "$(realpath "$0")")
CONF_DIR=/etc/nginx/conf.d

echo "Detected changes (diff):"
# Diff existing vs staging. "|| true" prevents exit on diff found.
diff -u -r --color=always "$CONF_DIR/" "$STAGING_DIR/" || true
echo ""

if [ "$1" = "diff" ]; then
    # echo "Diff check complete."
    # rm -rf "$STAGING_DIR"
    exit 0
fi

if [ "$1" = "test" ]; then
    echo "Running pre-flight validation on staged config..."
    TMP_NGINX_CONF=$(mktemp)

    # Create a temporary nginx.conf that points to STAGING_DIR instead of /etc/nginx/conf.d
    # We assume the standard include is "/etc/nginx/conf.d/*.conf"
    # We strictly replace that string with our staging path.
    sed "s|/etc/nginx/conf.d/\*\.conf|$STAGING_DIR/*.conf|g" /etc/nginx/nginx.conf >"$TMP_NGINX_CONF"

    if sudo nginx -t -c "$TMP_NGINX_CONF"; then
        echo "✓ Pre-flight validation passed."
        # Run debug dump by default for test target
        sudo nginx -T -c "$TMP_NGINX_CONF"
        rm "$TMP_NGINX_CONF"
        exit 0
    else
        echo "✗ Pre-flight validation FAILED."
        rm "$TMP_NGINX_CONF"
        exit 1
    fi
fi

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
sudo rm -rf "$STAGING_DIR"

echo "Verifying configuration..."
if [ -n "$DEBUG" ]; then
    echo "Debug mode enabled: running nginx -T"
    sudo nginx -t -c /etc/nginx/nginx.conf || true
    sudo nginx -T -c /etc/nginx/nginx.conf
fi

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
