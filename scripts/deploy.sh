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

    # Diff other system files
    echo "Checking other system files..."
    for DIR in "etc/systemd/system" "etc/continuwuity" "etc/conduwuit" "etc/matrix-conduit" "opt/stalwart/etc" "etc/matrix-synapse"; do
        if [ -d "$REPO_ROOT/$DIR" ]; then
            for FILE in "$REPO_ROOT/$DIR"/*; do
                [ -f "$FILE" ] || continue
                TARGET="/$DIR/$(basename "$FILE")"
                [ "$DIR" == "opt/stalwart/etc" ] && TARGET="/opt/stalwart/etc/$(basename "$FILE")"

                if [ -f "$TARGET" ]; then
                    echo "Diff for $TARGET:"
                    diff -u --color=always "$TARGET" "$FILE" || true
                else
                    echo "New file: $TARGET"
                fi
            done
        fi
    done
}

if [ "$1" = "diff" ]; then
    ENV="${2:-dev}"
    show_diff "$ENV"
    exit 0
fi

if [ "$1" = "test" ]; then
    ENV="${2:-dev}"
    echo "Running pre-flight validation for ENV=$ENV..."

    # DEBUG: List what we are working with
    echo "DEBUG: Staging Directory Contents:"
    find "$NGINX_CONF_SRC" -print

    TMP_WORK_DIR=$(mktemp -d)
    TMP_NGINX_CONF="$TMP_WORK_DIR/nginx.conf"
    TMP_CONF_D="$TMP_WORK_DIR/conf.d"
    mkdir -p "$TMP_CONF_D"

    # Copy config files to temp dir for testing, respecting secrets
    # Copy config files to temp dir for testing, respecting secrets
    # We scan recursively to find configs in dev/ or prod/ subdirs
    find "$NGINX_CONF_SRC" -name "*.conf" | while read -r FILE; do
        BASENAME=$(basename "$FILE")

        # Skip secrets.conf if it's not text (encrypted)
        if [ "$BASENAME" = "secrets.conf" ] && ! is_text_file "$FILE"; then
            echo "Skipping encrypted secrets.conf for test..."
            continue
        fi

        # Filter based on directory structure (dev/ vs prod/)
        if [[ "$FILE" == *"/dev/"* ]]; then
            if [ "$ENV" != "dev" ]; then continue; fi
        fi
        if [[ "$FILE" == *"/prod/"* ]]; then
            if [ "$ENV" != "prod" ]; then continue; fi
        fi

        # We copy all found .conf files to the flat temp directory
        # Since we use Makefile to only stage the correct ENV, we don't need to filter by name here anymore.
        cp "$FILE" "$TMP_CONF_D/"
    done

    # Rewrite absolute paths to the temp directory for testing
    # This prevents failures when a config includes another file that hasn't been deployed yet
    sed -i "s|/etc/nginx/conf.d/|$TMP_CONF_D/|g" "$TMP_CONF_D"/*.conf

    # Generate test nginx.conf
    # We strictly replace the include path
    sed "s|/etc/nginx/conf.d/\*\.conf|$TMP_CONF_D/*.conf|g" /etc/nginx/nginx.conf >"$TMP_NGINX_CONF"

    # DEBUG: Show what we are testing
    echo "DEBUG: Test Config Structure:"
    tree "$TMP_WORK_DIR" 2>/dev/null || ls -R "$TMP_WORK_DIR"

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
BACKUP_DIR=~/.nginx-ops/backups/nginx_backup_$(date +%s)
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

# Clean Install: Remove existing configs to prevent stale files
echo "Cleaning destination directory $DEST_CONF_DIR (preserving secrets.conf)..."
if [ -d "$DEST_CONF_DIR" ]; then
    # Find and delete files, excluding secrets.conf
    # We delete *.conf and *.disabled to keep it clean
    sudo find "$DEST_CONF_DIR" -maxdepth 1 -type f \( -name "*.conf" -o -name "*.disabled" \) ! -name "secrets.conf" -delete
fi

# Install configs
find "$NGINX_CONF_SRC" -name "*.conf" | while read -r FILE; do
    BASENAME=$(basename "$FILE")

    # Skip encrypted secrets
    if [ "$BASENAME" = "secrets.conf" ] && ! is_text_file "$FILE"; then
        echo "Skipping encrypted secrets.conf..."
        continue
    fi

    # Install to destination (flattening directory structure)
    echo "Installing $BASENAME..."
    sudo cp "$FILE" "$DEST_CONF_DIR/"
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
        sudo chown -R git:git /srv/git/
    fi

    # Deploy Homepage (already generated during local staging)
    if [ -f "$REPO_ROOT/scripts/homepage.html" ]; then
        echo "Deploying Homepage..."
        sudo mkdir -p /var/www
        sudo cp "$REPO_ROOT/scripts/homepage.html" /var/www/homepage.html
        sudo chown www-data:www-data /var/www/homepage.html
        sudo chmod 644 /var/www/homepage.html
    fi

    # Deploy System Files
    echo "Installing system files..."
    for DIR in "etc/systemd/system" "etc/continuwuity" "etc/conduwuit" "etc/matrix-conduit" "opt/stalwart/etc" "etc/matrix-synapse"; do
        if [ -d "$REPO_ROOT/$DIR" ]; then
            echo "Installing files from $DIR..."
            # For Stalwart, we need to make sure the path exists
            if [ "$DIR" == "opt/stalwart/etc" ]; then
                sudo mkdir -p /opt/stalwart/etc
            else
                sudo mkdir -p "/$DIR"
            fi

            sudo cp -r "$REPO_ROOT/$DIR"/* "/$DIR/"

            # Special handling for systemd: trigger daemon-reload
            if [ "$DIR" == "etc/systemd/system" ]; then
                echo "Triggering systemd daemon-reload..."
                sudo systemctl daemon-reload
            fi

            # Service Restarts
            if [ "$DIR" == "etc/conduwuit" ]; then
                echo "Restarting conduwuit service..."
                sudo systemctl restart conduwuit || echo "Warning: Failed to restart conduwuit"
            fi
            if [ "$DIR" == "etc/continuwuity" ]; then
                echo "Restarting continuwuity service..."
                sudo systemctl restart continuwuity || echo "Warning: Failed to restart continuwuity"
            fi
            if [ "$DIR" == "opt/stalwart/etc" ]; then
                echo "Restarting stalwart service..."
                sudo systemctl restart stalwart || echo "Warning: Failed to restart stalwart"
            fi
        fi
    done

    # Show deployed config files
    echo ""
    echo "Deployed configurations:"
    tree -a "$DEST_CONF_DIR" 2>/dev/null || ls -la "$DEST_CONF_DIR"

    echo "✓ Deployment successful."
else
    echo "✗ Configuration failed validation! Rolling back..."
    sudo cp "$BACKUP_DIR"/*.conf "$DEST_CONF_DIR/"
    [ -f "$BACKUP_DIR/gitweb.conf" ] && sudo cp "$BACKUP_DIR/gitweb.conf" /etc/gitweb.conf
    echo "Rollback complete. Verifying rollback..."
    sudo nginx -t
    exit 1
fi
