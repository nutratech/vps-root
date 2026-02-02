#!/bin/bash
set -e

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
            # Trigger the deployment service (allowed in sudoers)
            echo "Triggering deployment service..."
            sudo systemctl restart nutra-deploy.service

        else
            echo "Error: deploy.sh not found in staging!"
            exit 1
        fi

        echo "==============================================="
        echo "Deployment Complete."
        echo "==============================================="
    fi
done
