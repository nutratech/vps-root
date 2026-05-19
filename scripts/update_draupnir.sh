#!/bin/bash
set -e

REPO="the-draupnir-project/Draupnir"
INSTALL_DIR="/opt/draupnir"
SERVICE="draupnir"

# Fallback version if auto-detection fails
FALLBACK_VERSION="v3.1.0"

echo "Fetching latest release tag from GitHub ($REPO)..."
LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -n "$LATEST_TAG" ]; then
    VERSION="$LATEST_TAG"
    echo "Detected latest version: $VERSION"
else
    echo "Failed to fetch latest version (likely API rate limit or network issue)."
    if [ -n "$1" ]; then
        VERSION="$1"
        echo "Using provided version: $VERSION"
    else
        VERSION="$FALLBACK_VERSION"
        echo "Using fallback default version: $VERSION"
    fi
fi

# Allow explicit version override via argument
if [ -n "$1" ]; then
    VERSION="$1"
fi

TARBALL_URL="https://github.com/$REPO/archive/refs/tags/$VERSION.tar.gz"
TMP_DIR=$(mktemp -d)
BACKUP_DIR="/opt/draupnir_backups/$(date +%s)"

echo "Updating Draupnir to $VERSION..."
echo "Source: $TARBALL_URL"

# Download source tarball
echo "Downloading source..."
curl -L -o "$TMP_DIR/draupnir.tar.gz" "$TARBALL_URL"

if [ ! -s "$TMP_DIR/draupnir.tar.gz" ]; then
    echo "Download failed or file is empty."
    rm -rf "$TMP_DIR"
    exit 1
fi

# Extract to staging
STAGING_DIR="${INSTALL_DIR}_staging"
echo "Extracting to staging directory ($STAGING_DIR)..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
tar -xzf "$TMP_DIR/draupnir.tar.gz" --strip-components=1 -C "$STAGING_DIR"

# Install dependencies and build
echo "Installing dependencies..."
cd "$STAGING_DIR"
yarn install --frozen-lockfile

echo "Building TypeScript..."
yarn build

# Preserve production config if it exists
if [ -f "/etc/draupnir/production.yaml" ]; then
    echo "Production config found at /etc/draupnir/production.yaml — leaving intact."
fi

# Backup existing and swap in new build
mkdir -p /opt/draupnir_backups
if [ -d "$INSTALL_DIR" ]; then
    echo "Backing up existing installation to $BACKUP_DIR..."
    mv "$INSTALL_DIR" "$BACKUP_DIR"
fi
mv "$STAGING_DIR" "$INSTALL_DIR"

# Fix ownership
chown -R draupnir:draupnir "$INSTALL_DIR"

# Cleanup
rm -rf "$TMP_DIR"

# Restart service if running
if systemctl is-active --quiet "$SERVICE"; then
    echo "Restarting $SERVICE..."
    systemctl restart "$SERVICE"
else
    echo "$SERVICE is not currently running — skipping restart."
fi

echo "Update complete! Draupnir is now at $VERSION."
