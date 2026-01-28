#!/usr/bin/env python3
import re
import os
from flask import Flask, jsonify
import re
import requests
from flask import Flask, jsonify, request

app = Flask(__name__)

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


def parse_blocked_ips():
    if os.path.exists(BLOCKED_CONF_LOCAL):
        conf_path = BLOCKED_CONF_LOCAL
    else:
        conf_path = BLOCKED_CONF_SYSTEM

    if not os.path.exists(conf_path):
        return []

    entries = []
    current_comment = ""

    try:
        with open(conf_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                if line.startswith("#"):
                    current_comment = line.lstrip("# ").strip()
                    continue

                # Format: deny 1.2.3.4;
                match = re.match(r"^deny\s+([\d\.]+);", line)
                if match:
                    entries.append({"ip": match.group(1), "comment": current_comment})
    except Exception as e:
        print(f"Error parsing config: {e}")
        return []

    return entries


@app.route("/api/blocked")
def get_blocked():
    entries = parse_blocked_ips()
    return jsonify({"count": len(entries), "entries": entries})


@app.route("/api/health")
def health():
    return jsonify({"status": "ok"})


if __name__ == "__main__":
    # Access via Nginx proxy, so listening on localhost is fine
    app.run(host="127.0.0.1", port=5000)
