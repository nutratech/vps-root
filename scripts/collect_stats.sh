#!/bin/bash
# scripts/collect_stats.sh
# Needs to run as root (e.g., via systemd timer or cron)

# Wrapper to run the Python Stats Collector
# This script is called by systemd (nutra-stats.service)

PYTHON_SCRIPT="/opt/api/collect_stats.py"

if [ -f "$PYTHON_SCRIPT" ]; then
    /usr/bin/python3 "$PYTHON_SCRIPT"
else
    echo "Error: $PYTHON_SCRIPT not found!"
    exit 1
fi
