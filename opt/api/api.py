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
import secrets
import base64

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

# Matrix Bot Config
MATRIX_BOT_TOKEN = os.environ.get("MATRIX_BOT_TOKEN")
MATRIX_BOT_ROOM_ID = os.environ.get("MATRIX_BOT_ROOM_ID")
MATRIX_HOMESERVER_URL = os.environ.get(
    "MATRIX_HOMESERVER_URL", "https://matrix.nutra.tk"
)

CONTACT_INFO = {
    "email": os.environ.get("CONTACT_EMAIL", "shane@nutra.tk"),
    "matrix": os.environ.get("CONTACT_MATRIX", "@gamesguru:matrix.org, @gg:nutra.tk"),
    "gpg_description": base64.b64decode(
        os.environ.get("CONTACT_GPG_DESC_B64", "")
    ).decode("utf-8"),
    "gpg_public_key": base64.b64decode(
        os.environ.get("CONTACT_GPG_KEY_B64", "")
    ).decode("utf-8"),
}

STATS_FILE = "/opt/api/stats.json"
if not os.path.exists(STATS_FILE):
    STATS_FILE = os.path.join(os.getcwd(), "stats.json")


def validate_captcha(token):
    """Validates the Turnstile token with Cloudflare."""
    # Local Dev Bypass
    bypass_token = os.environ.get("CAPTCHA_BYPASS_TOKEN")
    if bypass_token and secrets.compare_digest(token, bypass_token):
        print("Captcha bypassed with token")
        return True

    url = "https://challenges.cloudflare.com/turnstile/v0/siteverify"
    data = {"secret": TURNSTILE_SECRET_KEY, "response": token}
    try:
        res = requests.post(url, data=data)
        result = res.json()
        return result.get("success", False)
    except Exception as e:
        print(f"Validation error: {e}")
        return False


def send_matrix_message(user_name, message):
    """Sends a message to the public Matrix room via the bot."""
    if not MATRIX_BOT_TOKEN or not MATRIX_BOT_ROOM_ID:
        print("Matrix bot not configured")
        return False

    url = f"{MATRIX_HOMESERVER_URL}/_matrix/client/v3/rooms/{MATRIX_BOT_ROOM_ID}/send/m.room.message"
    headers = {
        "Authorization": f"Bearer {MATRIX_BOT_TOKEN}",
        "Content-Type": "application/json",
    }
    # Sanitize inputs strictly? Matrix handles text, but let's be safe.
    # We send as formatted text for bolding the name.
    formatted_body = f"<strong>Guest ({user_name})</strong>: {message}"
    plain_body = f"Guest ({user_name}): {message}"

    payload = {
        "msgtype": "m.text",
        "body": plain_body,
        "format": "org.matrix.custom.html",
        "formatted_body": formatted_body,
    }

    try:
        res = requests.post(url, headers=headers, json=payload)
        if res.status_code == 200:
            return res.json().get("event_id")
        else:
            print(f"Matrix send failed: {res.status_code} {res.text}")
            return None
    except Exception as e:
        print(f"Matrix request error: {e}")
        return None


def get_matrix_replies(original_event_id):
    """Fetches replies to a specific event ID from the room history."""
    if not MATRIX_BOT_TOKEN or not MATRIX_BOT_ROOM_ID:
        return []

    # Fetch recent messages (last 50 should be enough for context)
    url = (
        f"{MATRIX_HOMESERVER_URL}/_matrix/client/v3/rooms/{MATRIX_BOT_ROOM_ID}/messages"
    )
    headers = {"Authorization": f"Bearer {MATRIX_BOT_TOKEN}"}
    params = {"dir": "b", "limit": 50}  # Backwards from latest

    replies = []
    try:
        res = requests.get(url, headers=headers, params=params)
        if res.status_code == 200:
            data = res.json()
            events = data.get("chunk", [])

            for event in events:
                # Look for m.room.message events
                if event.get("type") != "m.room.message":
                    continue

                content = event.get("content", {})
                relates_to = content.get("m.relates_to", {})

                # Check if it is a reply to our original_event_id
                # Structure: content -> m.relates_to -> m.in_reply_to -> event_id
                in_reply_to = relates_to.get("m.in_reply_to", {})
                if in_reply_to.get("event_id") == original_event_id:
                    # Found a reply!
                    replies.append(
                        {
                            "sender": event.get("sender"),
                            "body": content.get("body", "[Empty]"),
                            "timestamp": event.get("origin_server_ts"),
                        }
                    )
        return replies
    except Exception as e:
        print(f"Matrix history fetch error: {e}")
        return []


def get_matrix_presence(user_id):
    """Fetches presence status for a Matrix user."""
    # Check for empty or placeholder token
    if not MATRIX_BOT_TOKEN or MATRIX_BOT_TOKEN == "YOUR_BOT_ACCESS_TOKEN":
        print("Presence check skipped: No valid token")
        return "unknown"

    url = f"{MATRIX_HOMESERVER_URL}/_matrix/client/v3/presence/{user_id}/status"
    headers = {"Authorization": f"Bearer {MATRIX_BOT_TOKEN}"}

    try:
        res = requests.get(url, headers=headers, timeout=5)
        print(f"Presence check for {user_id}: {res.status_code} {res.text}")
        if res.status_code == 200:
            data = res.json()
            # "presence" can be "online", "offline", "unavailable"
            return data.get("presence", "offline")

        # If 401/403 (Bad Token) or 404, return unknown
        print(f"Presence fetch failed ({res.status_code}): {res.text}")
        return "unknown"
    except Exception as e:
        print(f"Presence fetch error: {e}")
        return "unknown"


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

        return jsonify(
            {"success": True, "message": f"Resume sent to {recipient_email}"}
        )

    except Exception as e:
        error_msg = str(e)
        print(f"Email error: {error_msg}")
        return jsonify({"error": f"Failed to send email: {error_msg}"}), 500


@app.route("/api/send-chat", methods=["POST"])
def send_chat():
    data = request.json
    token = data.get("token")
    name = data.get("name", "Anonymous")
    message = data.get("message")

    if not token:
        return jsonify({"error": "Missing token"}), 400
    if not message:
        return jsonify({"error": "Missing message"}), 400
    if len(message) > 500:
        return jsonify({"error": "Message too long"}), 400

    if not validate_captcha(token):
        return jsonify({"error": "Invalid captcha"}), 403

    event_id = send_matrix_message(name, message)
    if event_id:
        return jsonify({"success": True, "event_id": event_id})
    else:
        return jsonify({"error": "Failed to send message to Matrix"}), 500


@app.route("/api/check-reply", methods=["POST"])
def check_reply():
    data = request.json
    original_event_id = data.get("original_event_id")

    if not original_event_id:
        return jsonify({"error": "Missing event_id"}), 400

    replies = get_matrix_replies(original_event_id)
    return jsonify({"replies": replies})


@app.route("/api/server-info")
def server_info():
    stats = get_combined_stats()
    # Fetch admin presence (hardcoded for now as requested)
    presence = get_matrix_presence("@gg:nutra.tk")

    return jsonify(
        {
            "location": stats.get("server_location", "Unknown"),
            "time": stats.get("updated_at", ""),
            "admin_presence": presence,
        }
    )


if __name__ == "__main__":
    # Access via Nginx proxy, so listening on localhost is fine
    app.run(host="127.0.0.1", port=5000)
