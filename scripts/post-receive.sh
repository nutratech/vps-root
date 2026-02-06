#!/bin/bash
set -e

# Read input from stdin (oldrev newrev refname)
while read -r _oldrev _newrev refname; do
    # Only deploy if pushing to main or master
    if [ "$refname" = "refs/heads/main" ] || [ "$refname" = "refs/heads/master" ]; then
        echo "==============================================="
        echo "Deploying $refname via Git Reset Strategy..."
        echo "==============================================="

        # 1. Update the API Repo (Target)
        # We assume /opt/api is already a git clone of this repo
        echo "Updating /opt/api..."
        (
            unset GIT_DIR
            unset GIT_WORK_TREE
            cd /opt/api || exit 1
            git fetch origin
            git reset --hard origin/master
        )

        # 2. Self-update this hook
        # We assume this script is running from the bare repo root, so hooks/ is accessible.
        # Source is now the updated /opt/api repo.
        if [ -f "/opt/api/scripts/post-receive.sh" ]; then
            echo "Updating post-receive hook..."
            cp "/opt/api/scripts/post-receive.sh" hooks/post-receive
            chmod +x hooks/post-receive
        fi

        # 3. Restart API Service
        echo "Restarting Nutra API service..."
        sudo /usr/bin/systemctl restart nutra-api.service

        echo "==============================================="
        echo "Deployment Complete."
        echo "==============================================="
    fi
done
