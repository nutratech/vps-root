#!/bin/bash
# scripts/collect_stats.sh
# Needs to run as root (e.g., via systemd timer or cron)

OUTPUT_FILE="/opt/api/stats.json"

# Collect SSHD stats
SSHD_BANNED=$(fail2ban-client status sshd | grep "Currently banned" | awk '{print $NF}')
SSHD_TOTAL=$(fail2ban-client status sshd | grep "Total banned" | awk '{print $NF}')
SSHD_LIST=$(fail2ban-client status sshd | grep "Banned IP list" | cut -d: -f2 | tr -cd '[:print:]' | xargs)

# Collect Git Scraper stats (if active)
GIT_BANNED=$(fail2ban-client status nginx-git-scrapers | grep "Currently banned" | awk '{print $NF}')
GIT_TOTAL=$(fail2ban-client status nginx-git-scrapers | grep "Total banned" | awk '{print $NF}')
GIT_LIST=$(fail2ban-client status nginx-git-scrapers | grep "Banned IP list" | cut -d: -f2 | tr -cd '[:print:]' | xargs)
if [ -z "$GIT_BANNED" ]; then GIT_BANNED=0; fi
if [ -z "$GIT_TOTAL" ]; then GIT_TOTAL=0; fi

# Write JSON
cat <<EOF >"$OUTPUT_FILE"
{
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "sshd": {
    "currently_banned": ${SSHD_BANNED:-0},
    "total_banned": ${SSHD_TOTAL:-0},
    "banned_ips": "${SSHD_LIST:-}" 
  },
  "nginx_git_scrapers": {
    "currently_banned": ${GIT_BANNED:-0},
    "total_banned": ${GIT_TOTAL:-0},
    "banned_ips": "${GIT_LIST:-}"
  },
  "server_location": "San Jose, CA" 
}
EOF
chown www-data:www-data "$OUTPUT_FILE"
chmod 644 "$OUTPUT_FILE"
