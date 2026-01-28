#!/usr/bin/env python3
import re
import os
from flask import Flask, jsonify
import re
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)


@app.route("/")
def index():
    return jsonify(
        {
            "service": "Nutra API",
            "description": "Backend API for Nutra.tk services",
            "endpoints": ["/api/blocked", "/api/contact", "/api/resume", "/api/health"],
        }
    )


# Constants
BLOCKED_CONF_LOCAL = (
    "/home/shane/repos/nutra/vps-root/etc/nginx/conf.d/blocked_ips.conf"
)
BLOCKED_CONF_SYSTEM = "/etc/nginx/conf.d/blocked_ips.conf"

# Cloudflare Turnstile Secret (Get from ENV or fallback)
TURNSTILE_SECRET_KEY = os.environ["TURNSTILE_SECRET_KEY"]
CONTACT_INFO = {
    "email": os.environ.get("CONTACT_EMAIL", "shane@nutra.tk"),
    "matrix": os.environ.get("CONTACT_MATRIX", "@gamesguru:matrix.org"),
    "gpg": os.environ.get(
        "CONTACT_GPG",
        """pub   ed25519/CDBCCB44A608363E 2025-09-11 [SC]
      C6662F132E169C4802627B1ECDBCCB44A608363E
uid                 [  full  ] Shane J. (GIT SIGN+ENCRYPT KEY [DESKTOP])
uid                 [  full  ] gamesguru (GitHub) <30691680+gamesguru@users.noreply.github.com>
uid                 [  full  ] gamesguru (GitLab) <25245323-gamesguru@users.noreply.gitlab.com>
uid                 [  full  ] gg@desktop <chown_tee@proton.me>
sub   cv25519/CA76D7960067EE77 2025-09-11 [E]
      C884FDED5E44D4EEC34F574ACA76D7960067EE77""",
    ),
}

STATS_FILE = "/opt/api/stats.json"


def validate_captcha(token):
    """Validates the Turnstile token with Cloudflare."""
    url = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
    data = {"secret": TURNSTILE_SECRET_KEY, "response": token}
    try:
        res = requests.post(url, data=data)
        result = res.json()
        return result.get("success", False)
    except Exception as e:
        print(f"Validation error: {e}")
        return False


def get_combined_stats():
    # 1. Parse Nginx Blocked IPs (Manual)
    nginx_entries = []
    current_comment = ""
    conf_path = (
        BLOCKED_CONF_LOCAL
        if os.path.exists(BLOCKED_CONF_LOCAL)
        else BLOCKED_CONF_SYSTEM
    )

    if os.path.exists(conf_path):
        try:
            with open(conf_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    if line.startswith("#"):
                        current_comment = line.lstrip("# ").strip()
                        continue
                    match = re.match(r"^deny\s+([\d\.]+);", line)
                    if match:
                        nginx_entries.append(
                            {"ip": match.group(1), "comment": current_comment}
                        )
        except Exception as e:
            print(f"Error parsing nginx config: {e}")

    # 2. Read Fail2Ban Stats
    f2b_stats = {}
    if os.path.exists(STATS_FILE):
        try:
            with open(STATS_FILE, "r") as f:
                f2b_stats = json.load(f)
        except Exception as e:
            print(f"Error parsing stats.json: {e}")

    return {
        "nginx_manual": {"count": len(nginx_entries), "entries": nginx_entries},
        "fail2ban": f2b_stats.get("sshd", {}),
        "git_scrapers": f2b_stats.get("nginx_git_scrapers", {}),
        "server_location": f2b_stats.get("server_location", "Unknown"),
        "updated_at": f2b_stats.get("updated_at", ""),
    }


@app.route("/api/contact", methods=["POST"])
def contact():
    data = request.json
    token = data.get("token")
    if not token:
        return jsonify({"error": "Missing token"}), 400

    if validate_captcha(token):
        return jsonify(CONTACT_INFO)

    return jsonify({"error": "Invalid captcha"}), 403


@app.route("/api/blocked")
def get_blocked():
    return jsonify(get_combined_stats())


@app.route("/api/health")
def health():
    return jsonify({"status": "ok"})


@app.route("/api/resume", methods=["POST"])
def resume():
    data = request.json
    token = data.get("token")
    if not token:
        return jsonify({"error": "Missing token"}), 400

    if validate_captcha(token):
        # Allow defining resume path via env, but default to standard location
        resume_path = os.environ.get("RESUME_PATH", "/var/www/cv/swe/resume.pdf")
        if os.path.exists(resume_path):
            from flask import send_file

            return send_file(
                resume_path, as_attachment=True, download_name="resume.pdf"
            )
        else:
            return jsonify({"error": "Resume file not found on server"}), 404

    return jsonify({"error": "Invalid captcha"}), 403


if __name__ == "__main__":
    # Access via Nginx proxy, so listening on localhost is fine
    app.run(host="127.0.0.1", port=5000)
