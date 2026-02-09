#!/bin/bash
set -e

# Default fallback version if auto-detection fails
FALLBACK_VERSION="v1.12.9"
REPO_OWNER="element-hq"

# Try to get the latest version from GitHub API
echo "Fetching latest version tag from GitHub ($REPO_OWNER)..."
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO_OWNER/element-web/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -n "$LATEST_TAG" ]; then
    VERSION="$LATEST_TAG"
    echo "Detected latest version: $VERSION"
else
    echo "Failed to fetch latest version (likely API rate limit or network issue)."
    # If user provided an argument, use it; otherwise use fallback
    if [ -n "$1" ]; then
        VERSION="$1"
        echo "Using provided version: $VERSION"
    else
        VERSION="$FALLBACK_VERSION"
        echo "Using fallback default version: $VERSION"
    fi
fi

# Override if argument is provided explicitly (even if fetch succeeded, maybe user wants specific version)
if [ -n "$1" ]; then
    VERSION="$1"
fi

URL="https://github.com/$REPO_OWNER/element-web/releases/download/$VERSION/element-$VERSION.tar.gz"
DEST="/var/www/element"
TMP_DIR=$(mktemp -d)
BACKUP_DIR="/var/www/element_backups/$(date +%s)"

echo "Updating Element Web to $VERSION..."
echo "Download URL: $URL"

# Download
echo "Downloading..."
curl -L -o "$TMP_DIR/element.tar.gz" "$URL"

# Verify download
if [ ! -s "$TMP_DIR/element.tar.gz" ]; then
    echo "Download failed or file is empty."
    echo "URL tried: $URL"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Prepare backup
echo "Backing up existing installation..."
mkdir -p /var/www/element_backups
if [ -d "$DEST" ]; then
    sudo mv "$DEST" "$BACKUP_DIR"
    echo "Backup created at $BACKUP_DIR"
else
    echo "No existing installation found at $DEST"
fi

# Extract
echo "Extracting..."
sudo mkdir -p "$DEST"
sudo tar -xzf "$TMP_DIR/element.tar.gz" --strip-components=1 -C "$DEST"

# Restore config
if [ -f "$BACKUP_DIR/config.json" ]; then
    echo "Restoring config.json..."
    sudo cp "$BACKUP_DIR/config.json" "$DEST/config.json"
else
    echo "Warning: No config.json found in backup to restore."
fi

# Set permissions
echo "Setting permissions..."
sudo chown -R www-data:www-data "$DEST"
sudo chmod -R 755 "$DEST"

# Cleanup
rm -rf "$TMP_DIR"

echo "Update complete! Element Web is now at $VERSION."
