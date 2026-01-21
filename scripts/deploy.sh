#!/bin/bash
set -e

# Default to the parent directory of this script (Repo Root)
REPO_ROOT=$(dirname "$(dirname "$(realpath "$0")")")
NGINX_CONF_SRC="$REPO_ROOT/etc/nginx/conf.d"
GITWEB_CONF_SRC="$REPO_ROOT/etc/gitweb.conf"
DEST_CONF_DIR="/etc/nginx/conf.d"

# Helper to check if file is text (decrypted)
is_text_file() {
    grep -qI . "$1"
}

echo "Source: $REPO_ROOT"

# Function to show diff
show_diff() {
    local ENV="$1"
    echo "Detected changes (diff) for ENV=$ENV:"
    # We can't use simple diff -r because we need to exclude secrets.conf if encrypted
    # So we loop through source files
    for FILE in "$NGINX_CONF_SRC"/*.conf; do
        BASENAME=$(basename "$FILE")
        if [ "$BASENAME" = "secrets.conf" ] && ! is_text_file "$FILE"; then
            echo "Skipping encrypted secrets.conf diff..."
            continue
        fi

        # Logic to check against default.conf
        TARGET_FILE="$DEST_CONF_DIR/$BASENAME"

        # Generic handling for *.dev.conf and *.prod.conf
        if [[ "$BASENAME" =~ ^(.*)\.(dev|prod)\.conf$ ]]; then
            STEM="${BASH_REMATCH[1]}"
            CONF_ENV="${BASH_REMATCH[2]}"

            if [ "$CONF_ENV" == "$ENV" ]; then
                TARGET_FILE="$DEST_CONF_DIR/$STEM.conf"
            else
                continue
            fi
        fi

        if [ -f "$TARGET_FILE" ]; then
             diff -u --color=always "$TARGET_FILE" "$FILE" || true
        else
             echo "New file: $BASENAME"
             # Show content of new file as diff (dev null vs new)
             diff -u --color=always /dev/null "$FILE" || true
        fi
    done

    # Diff gitweb.conf
    if [ -f "$GITWEB_CONF_SRC" ]; then
        diff -u --color=always /etc/gitweb.conf "$GITWEB_CONF_SRC" || true
    fi
}

if [ "$1" = "diff" ]; then
    ENV="${2:-dev}"
    show_diff "$ENV"
    exit 0
fi

if [ "$1" = "test" ]; then
    ENV="${2:-dev}"
    echo "Running pre-flight validation for ENV=$ENV..."
    TMP_WORK_DIR=$(mktemp -d)
    TMP_NGINX_CONF="$TMP_WORK_DIR/nginx.conf"
    TMP_CONF_D="$TMP_WORK_DIR/conf.d"
    mkdir -p "$TMP_CONF_D"

    # Copy config files to temp dir for testing, respecting secrets
    for FILE in "$NGINX_CONF_SRC"/*.conf; do
        BASENAME=$(basename "$FILE")
        if [ "$BASENAME" = "secrets.conf" ] && ! is_text_file "$FILE"; then
            echo "Skipping encrypted secrets.conf for test..."
            continue
        fi

        # Generic handling for *.dev.conf and *.prod.conf
        if [[ "$BASENAME" =~ ^(.*)\.(dev|prod)\.conf$ ]]; then
            STEM="${BASH_REMATCH[1]}"
            CONF_ENV="${BASH_REMATCH[2]}"

            if [ "$CONF_ENV" == "$ENV" ]; then
                cp "$FILE" "$TMP_CONF_D/$STEM.conf"
            else
                continue
            fi
        else
            cp "$FILE" "$TMP_CONF_D/"
        fi
    done

    # Generate test nginx.conf
    # We strictly replace the include path
    sed "s|/etc/nginx/conf.d/\*\.conf|$TMP_CONF_D/*.conf|g" /etc/nginx/nginx.conf >"$TMP_NGINX_CONF"

    if sudo nginx -t -c "$TMP_NGINX_CONF"; then
        echo "✓ Pre-flight validation passed."
        if [ -n "$DEBUG" ]; then
            sudo nginx -T -c "$TMP_NGINX_CONF"
        fi
        rm -rf "$TMP_WORK_DIR"
        exit 0
    else
        echo "✗ Pre-flight validation FAILED."
        sudo nginx -T -c "$TMP_NGINX_CONF"
        rm -rf "$TMP_WORK_DIR"
        exit 1
    fi
fi

# Create timestamped backup
BACKUP_DIR=~/nginx_backup_$(date +%s)
echo "Creating backup at $BACKUP_DIR..."
mkdir -p "$BACKUP_DIR"
if sudo ls "$DEST_CONF_DIR"/*.conf >/dev/null 2>&1; then
    sudo cp "$DEST_CONF_DIR"/*.conf "$BACKUP_DIR/"
fi
[ -f /etc/gitweb.conf ] && sudo cp /etc/gitweb.conf "$BACKUP_DIR/gitweb.conf"

# ENV is passed as first argument if not diff/test, default to dev
ENV="${1:-dev}"
echo "Deploying for environment: $ENV"

# Always show diff before installing
show_diff "$ENV"

echo "Installing new configurations..."

# Cleanup disabled configurations
for FILE in "$NGINX_CONF_SRC"/*.conf.disabled; do
    [ -e "$FILE" ] || continue
    BASENAME=$(basename "$FILE")
    if [[ "$BASENAME" =~ ^(.*)\.conf\.disabled$ ]]; then
        STEM="${BASH_REMATCH[1]}"
        if [ -f "$DEST_CONF_DIR/$STEM.conf" ]; then
            echo "Removing disabled config: $STEM.conf"
            sudo rm "$DEST_CONF_DIR/$STEM.conf"
        fi
    fi
done

for FILE in "$NGINX_CONF_SRC"/*.conf; do
    BASENAME=$(basename "$FILE")

    # Skip encrypted secrets
    if [ "$BASENAME" = "secrets.conf" ] && ! is_text_file "$FILE"; then
        echo "Skipping encrypted secrets.conf..."
        continue
    fi

    # Generic handling for *.dev.conf and *.prod.conf
    if [[ "$BASENAME" =~ ^(.*)\.(dev|prod)\.conf$ ]]; then
        STEM="${BASH_REMATCH[1]}"
        CONF_ENV="${BASH_REMATCH[2]}"

        if [ "$CONF_ENV" == "$ENV" ]; then
            echo "Installing $BASENAME as $STEM.conf..."
            sudo cp "$FILE" "$DEST_CONF_DIR/$STEM.conf"
        else
            echo "Skipping mismatch config: $BASENAME"
            continue
        fi
    else
        # Install all other configs as-is
        sudo cp "$FILE" "$DEST_CONF_DIR/"
    fi
done

echo "Verifying configuration..."
if [ -n "$DEBUG" ]; then
    echo "Debug mode enabled: running nginx -T"
    sudo nginx -t -c /etc/nginx/nginx.conf || true
    sudo nginx -T -c /etc/nginx/nginx.conf
fi

if sudo nginx -t; then
    echo "Configuration is valid. Reloading Nginx..."
    sudo nginx -s reload

    # Deploy gitweb.conf if it exists
    if [ -f "$GITWEB_CONF_SRC" ]; then
        echo "Deploying gitweb.conf..."
        sudo cp "$GITWEB_CONF_SRC" /etc/gitweb.conf
    fi

    # Deploy Gitweb frontend assets (Dev Only)
    if [ "$ENV" == "dev" ] && [ -d "$REPO_ROOT/scripts/gitweb-simplefrontend" ]; then
        echo "Generating services map..."
        if [ -f "$REPO_ROOT/scripts/gen_services_map.py" ]; then
            python3 "$REPO_ROOT/scripts/gen_services_map.py"
        fi

        echo "Deploying Gitweb frontend..."
        sudo cp -r "$REPO_ROOT/scripts/gitweb-simplefrontend/"* /srv/git/
        sudo chown -R www-data:www-data /srv/git/
    fi

    # Deploy Homepage
    if [ -f "$REPO_ROOT/scripts/homepage.html" ]; then
        echo "Deploying Homepage..."
        sudo mkdir -p /var/www
        sudo cp "$REPO_ROOT/scripts/homepage.html" /var/www/homepage.html
        sudo chown www-data:www-data /var/www/homepage.html
        sudo chmod 644 /var/www/homepage.html
    fi

    echo "✓ Deployment successful."
else
    echo "✗ Configuration failed validation! Rolling back..."
    sudo cp "$BACKUP_DIR"/*.conf "$DEST_CONF_DIR/"
    [ -f "$BACKUP_DIR/gitweb.conf" ] && sudo cp "$BACKUP_DIR/gitweb.conf" /etc/gitweb.conf
    echo "Rollback complete. Verifying rollback..."
    sudo nginx -t
    exit 1
fi
