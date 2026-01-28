import re
import os
import json
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.text import MIMEText
from email import encoders, utils
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
    "gpg_description": """pub   ed25519/CDBCCB44A608363E 2025-09-11 [SC]
      C6662F132E169C4802627B1ECDBCCB44A608363E
uid  Shane J. (GIT SIGN+ENCRYPT KEY [DESKTOP])
uid  gamesguru (GitHub) <30691680+gamesguru@users.noreply.github.com>
uid  gamesguru (GitLab) <25245323-gamesguru@users.noreply.gitlab.com>
uid  gg@desktop <chown_tee@proton.me>
sub   cv25519/CA76D7960067EE77 2025-09-11 [E]
      C884FDED5E44D4EEC34F574ACA76D7960067EE77""",
    "gpg_public_key": """-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: GnuPG v2

mDMEaMK+LxYJKwYBBAHaRw8BAQdArXbotsYIylKgx3uvcaQYP2TFFkcAKP6WsuVe
hf/CLHu0KVNoYW5lIEouIChHSVQgU0lHTitFTkNSWVBUIEtFWSBbREVTS1RPUF0p
iJMEExYIADsCGwMFCwkIBwIGFQoJCAsCBBYCAwECHgECF4AWIQTGZi8TLhacSAJi
ex7NvMtEpgg2PgUCaMMBDAIZAQAKCRDNvMtEpgg2PuYXAP9FmVrMELg0lkaC+6Hc
uFG1c3LmuUN41lBzBtOLAZnNRgEA1y+FEIvYQS6n71lfaluAhoEpVM2Bt8NGyrbn
+JaoaAG0QGdhbWVzZ3VydSAoR2l0SHViKSA8MzA2OTE2ODArZ2FtZXNndXJ1QHVz
ZXJzLm5vcmVwbHkuZ2l0aHViLmNvbT6IkwQTFgoAOxYhBMZmLxMuFpxIAmJ7Hs28
y0SmCDY+BQJow1Y9AhsDBQsJCAcCAiICBhUKCQgLAgQWAgMBAh4HAheAAAoJEM28
y0SmCDY+d9sA/jMj1IksCEAI1LoXm7WT8Cl1P0DzMtvfVEYGlmYJKwAEAQC8V/XT
kN8rVqjn15I7CHzpl1uzwblWB2EONRDLYNIhDrRAZ2FtZXNndXJ1IChHaXRMYWIp
IDwyNTI0NTMyMy1nYW1lc2d1cnVAdXNlcnMubm9yZXBseS5naXRsYWIuY29tPoiT
BBMWCgA7FiEExmYvEy4WnEgCYnsezbzLRKYINj4FAmjDVkgCGwMFCwkIBwICIgIG
FQoJCAsCBBYCAwECHgcCF4AACgkQzbzLRKYINj7uhAEAu4jowCYO96c5tLkfubzo
ALDzGmU2B4jtcjvNRPKtfh4BAMWRcpz41GhPVcwbLvvVuucks4NKfc2atS4/+i1z
B+YHtCBnZ0BkZXNrdG9wIDxjaG93bl90ZWVAcHJvdG9uLm1lPoiQBBMWCgA4FiEE
xmYvEy4WnEgCYnsezbzLRKYINj4FAmlIqUECGwMFCwkIBwIGFQoJCAsCBBYCAwEC
HgECF4AACgkQzbzLRKYINj6t/gD9FlMrEv1ZfTwSZWnlFDkiPZNVcPLtTdDcup8p
qlOS9o8BAI1V2mVr8gycAUc9K3JFSIYUGrqzyFiGIlpeYLpmcecLuDgEaMK+LxIK
KwYBBAGXVQEFAQEHQJAgIeT9A28rgDYTEIPLI4cG8/1QqzuOqoDtFQ3XJNYLAwEI
B4h4BBgWCAAgFiEExmYvEy4WnEgCYnsezbzLRKYINj4FAmjCvi8CGwwACgkQzbzL
RKYINj5GVwD+LZzVDnJivWZmlOdjnjaMYtYmB/DMSFwZ+FRcNsxpDM4BAP0r6fFc
Kpv1aDkbgz7P85+tEEv0cLSMuRKrw+fB9ZoA
=BZAp
-----END PGP PUBLIC KEY BLOCK-----""",
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
                content = f.read().strip()
                if content:
                    # Remove any non-printable characters manually
                    import string
                    printable = set(string.printable)
                    content = "".join(filter(lambda x: x in printable, content))
                    f2b_stats = json.loads(content)
        except Exception as e:
            print(f"Error parsing stats.json: {e}")
            f2b_stats = {}

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


@app.route("/api/send-resume", methods=["POST"])
def send_resume():
    data = request.json
    token = data.get("token")
    recipient_email = data.get("email")

    if not token:
        return jsonify({"error": "Missing token"}), 400
    if not recipient_email:
        return jsonify({"error": "Missing email"}), 400

    # Basic email validation
    if not re.match(r"^[^@]+@[^@]+\.[^@]+$", recipient_email):
        return jsonify({"error": "Invalid email address"}), 400

    # Validate fresh captcha token
    if not validate_captcha(token):
        return jsonify({"error": "Invalid captcha"}), 403

    resume_path = os.environ.get("RESUME_PATH", "/var/www/cv/swe/resume.pdf")
    if not os.path.exists(resume_path):
        return jsonify({"error": "Resume file not found"}), 404

    try:
        # SMTP config from env
        smtp_host = os.environ.get("SMTP_HOST", "127.0.0.1")
        smtp_port = int(os.environ.get("SMTP_PORT", 587))
        smtp_user = os.environ["SMTP_USER"]
        smtp_pass = os.environ["SMTP_PASSWORD"]
        smtp_from_env = os.environ["SMTP_FROM"]
        
        # Extract clean email for envelope sender
        _, envelope_from = utils.parseaddr(smtp_from_env)
        if not envelope_from or "@" not in envelope_from:
            envelope_from = smtp_user if "@" in smtp_user else "services@nutra.tk"

        # Build email
        msg = MIMEMultipart()
        # Ensure the From address in the header matches the envelope sender for deliverability
        msg["From"] = f"Shane J. <{envelope_from}>"
        msg["To"] = recipient_email
        msg["Subject"] = "Shane J. - Resume"
        msg["Date"] = utils.formatdate(localtime=True)
        msg["Message-ID"] = utils.make_msgid(domain="nutra.tk")

        body = """Hi,

You requested a copy of Shane J.'s resume. Please find it attached.

Best regards,
Nutra.tk
"""
        msg.attach(MIMEText(body, "plain"))

        # Attach PDF with correct type
        with open(resume_path, "rb") as f:
            part = MIMEBase("application", "pdf")
            part.set_payload(f.read())
            encoders.encode_base64(part)
            part.add_header("Content-Disposition", "attachment", filename="resume.pdf")
            msg.attach(part)

        # Send
        with smtplib.SMTP(smtp_host, smtp_port, timeout=10) as server:
            if smtp_user and smtp_pass:
                if smtp_port != 465:
                    server.starttls()
                server.login(smtp_user, smtp_pass)
            # Use clean envelope_from
            server.sendmail(envelope_from, recipient_email, msg.as_string())

        return jsonify({"success": True, "message": f"Resume sent to {recipient_email}"})

    except Exception as e:
        error_msg = str(e)
        print(f"Email error: {error_msg}")
        return jsonify({"error": f"Failed to send email: {error_msg}"}), 500


@app.route("/api/server-info")
def server_info():
    stats = get_combined_stats()
    return jsonify(
        {
            "location": stats.get("server_location", "Unknown"),
            "time": stats.get("updated_at", ""),
        }
    )


if __name__ == "__main__":
    # Access via Nginx proxy, so listening on localhost is fine
    app.run(host="127.0.0.1", port=5000)
