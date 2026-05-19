#!/bin/bash
set -e

# Default fallback version if auto-detection fails
FALLBACK_VERSION="v1.16.1"
REPO="SableClient/Sable"

# Try to get the latest version from GitHub API
echo "Fetching latest version tag from GitHub ($REPO)..."
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

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

# Override if argument is provided explicitly
if [ -n "$1" ]; then
    VERSION="$1"
fi

URL="https://github.com/$REPO/releases/download/$VERSION/sable-$VERSION.tar.gz"
DEST="/var/www/sable"
TMP_DIR=$(mktemp -d)
BACKUP_DIR="/var/www/sable_backups/$(date +%s)"

echo "Updating Sable to $VERSION..."
echo "Download URL: $URL"

# Download
echo "Downloading..."
curl -L -o "$TMP_DIR/sable.tar.gz" "$URL"

# Verify download
if [ ! -s "$TMP_DIR/sable.tar.gz" ]; then
    echo "Download failed or file is empty."
    echo "URL tried: $URL"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract to a staging directory
STAGING_DIR="${DEST}_staging"
echo "Extracting to staging directory ($STAGING_DIR)..."
sudo rm -rf "$STAGING_DIR"
sudo mkdir -p "$STAGING_DIR"
sudo tar -xzf "$TMP_DIR/sable.tar.gz" --strip-components=1 -C "$STAGING_DIR"

# Copy config from current installation if it exists
if [ -d "$DEST" ] && [ -f "$DEST/config.json" ]; then
    echo "Copying config.json from current installation..."
    sudo cp "$DEST/config.json" "$STAGING_DIR/config.json"
fi

# Set permissions on staging
echo "Setting permissions..."
sudo chown -R www-data:www-data "$STAGING_DIR"
sudo chmod -R 755 "$STAGING_DIR"

# Atomically swap and backup
echo "Backing up existing installation and swapping in new version..."
mkdir -p /var/www/sable_backups
if [ -d "$DEST" ]; then
    sudo mv "$DEST" "$BACKUP_DIR"
    echo "Backup created at $BACKUP_DIR"
fi
sudo mv "$STAGING_DIR" "$DEST"

# Cleanup
rm -rf "$TMP_DIR"

echo "Update complete! Sable is now at $VERSION."
