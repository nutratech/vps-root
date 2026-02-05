#!/bin/bash
set -e
set -x

# Configuration
STAGING_DIR="$HOME/.nginx-ops/staging"
DEPLOY_SCRIPT="$STAGING_DIR/scripts/deploy.sh"

# Read input from stdin (oldrev newrev refname)
while read oldrev newrev refname; do
    # Only deploy if pushing to main or master
    if [ "$refname" = "refs/heads/main" ] || [ "$refname" = "refs/heads/master" ]; then
        echo "==============================================="
        echo "Deploying $refname..."
        echo "==============================================="

        # 1. Checkout code to staging directory
        echo "Checking out code to $STAGING_DIR..."
        mkdir -p "$STAGING_DIR"
        # Determine branch name from ref
        BRANCH_NAME=$(basename "$refname")
        git --work-tree="$STAGING_DIR" --git-dir="." checkout -f "$BRANCH_NAME"

        # Self-update the hook
        if [ -f "$STAGING_DIR/scripts/post-receive.sh" ]; then
            echo "Updating post-receive hook..."
            cp "$STAGING_DIR/scripts/post-receive.sh" hooks/post-receive
            chmod +x hooks/post-receive
        fi

        # 2. Run Deployment Script
        if [ -f "$DEPLOY_SCRIPT" ]; then
            echo "Running deployment script..."
            # Execute in a subshell or directly
            # Pass 'prod' or 'dev' based on where we are?
            # For now, let's assume this repo is PROD or DEV based on hostname or manual setup
            # But usually vps-root implies prod-like behavior or specific env.
            # Let's try to detect or default to prod for 'vps-root'

            # Note: The Makefile stages to ~/.nginx-ops/staging too.
            # We are mimicking that info.

            # Fix permissions just in case
            # Execute
            echo "Deploying API..."
            # 1. Copy API files
            # Note: We assume the destination directory /opt/api/src exists and is owned by git.
            cp "$STAGING_DIR/opt/api/src/api.py" /opt/api/src/api.py
            chmod +x /opt/api/src/api.py

            if [ -f "$STAGING_DIR/opt/api/src/collect_stats.py" ]; then
                cp "$STAGING_DIR/opt/api/src/collect_stats.py" /opt/api/src/collect_stats.py
                chmod +x /opt/api/src/collect_stats.py
            fi

            # 2. Restart API Service
            echo "Restarting Nutra API service..."
            sudo /usr/bin/systemctl restart nutra-api.service

        else
            echo "Error: deploy.sh not found in staging!"
            exit 1
        fi

        echo "==============================================="
        echo "Deployment Complete."
        echo "==============================================="
    fi
done
