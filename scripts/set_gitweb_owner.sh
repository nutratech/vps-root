#!/bin/bash
set -e

OWNER="$1"
PROJECT_ROOT="/srv/git/projects"

if [ -z "$OWNER" ]; then
    echo "Usage: $0 \"Owner Name\""
    exit 1
fi

if [ ! -d "$PROJECT_ROOT" ]; then
    echo "Error: Directory $PROJECT_ROOT not found."
    exit 1
fi

echo "Setting 'gitweb.owner' to '$OWNER' for all repos in $PROJECT_ROOT..."

# Iterate over directories ending in .git
find "$PROJECT_ROOT" -name "*.git" -type d | while read -r repo; do
    if [ -f "$repo/config" ]; then
        echo "Updating $repo..."
        git config --file "$repo/config" gitweb.owner "$OWNER"
    else
        echo "Skipping $repo (no config file found)"
    fi
done

echo "Done."
