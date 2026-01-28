#!/usr/bin/env python3
import re
from datetime import datetime
from pathlib import Path

# Paths relative to repo root
REPO_ROOT = Path(__file__).parent.parent
BLOCKED_CONF = REPO_ROOT / "etc/nginx/conf.d/blocked_ips.conf"
OUTPUT_HTML = REPO_ROOT / "opt/my-website/static/blocked.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nutratech | Blocked IPs</title>
    <style>
        :root {{
            --bg-color: #0f172a;
            --text-color: #e2e8f0;
            --card-bg: #1e293b;
            --border-color: #334155;
            --accent-color: #ef4444;
        }}
        body {{
            font-family: 'Inter', system-ui, -apple-system, sans-serif;
            background-color: var(--bg-color);
            color: var(--text-color);
            line-height: 1.6;
            margin: 0;
            padding: 2rem;
            max-width: 800px;
            margin: 0 auto;
        }}
        h1 {{
            color: #fff;
            border-bottom: 2px solid var(--border-color);
            padding-bottom: 1rem;
        }}
        .stat-card {{
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 2rem;
            text-align: center;
            margin: 2rem 0;
        }}
        .big-number {{
            font-size: 4rem;
            font-weight: 700;
            color: var(--accent-color);
            line-height: 1;
        }}
        .label {{
            font-size: 1.2rem;
            color: #94a3b8;
            margin-top: 0.5rem;
        }}
        .ip-list {{
            background: var(--card-bg);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 1.5rem;
            font-family: monospace;
            max-height: 400px;
            overflow-y: auto;
        }}
        .ip-item {{
            padding: 0.25rem 0;
            border-bottom: 1px solid #33415555;
            display: flex;
            justify-content: space-between;
        }}
        .ip-item:last-child {{ border-bottom: none; }}
        .comment {{ color: #64748b; font-style: italic; }}
        footer {{
            margin-top: 3rem;
            text-align: center;
            color: #64748b;
            font-size: 0.875rem;
        }}
    </style>
</head>
<body>
    <h1>🛡️ Global Ban List</h1>
    
    <div class="stat-card">
        <div class="big-number">{count}</div>
        <div class="label">Total Blocked IP Addresses</div>
    </div>

    <h2>Blocked Entries</h2>
    <div class="ip-list">
        {ip_list_html}
    </div>

    <footer>
        <p>Generated on {generated_at} from Nginx configuration.</p>
        <p>Nutratech Infrastructure Protection</p>
    </footer>
</body>
</html>"""


def parse_blocked_ips():
    if not BLOCKED_CONF.exists():
        print(f"Warning: {BLOCKED_CONF} not found.")
        return []

    entries = []
    current_comment = ""

    with open(BLOCKED_CONF, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Capture comments that precede blocks
            if line.startswith("#"):
                current_comment = line.lstrip("# ").strip()
                continue

            # Parse deny lines
            # Format: deny 1.2.3.4;
            match = re.match(r"^deny\s+([\d\.]+);", line)
            if match:
                ip = match.group(1)
                entries.append({"ip": ip, "comment": current_comment})
                # Keep comment for next IP if it looks like a group header?
                # Actually, typical format is:
                # # Header
                # deny x;
                # deny y;
                # So we keep the comment until a new blank line or new comment appears.

                # However, usually there are blank lines between groups.
                # Let's simple keep the last comment seen.
            else:
                # If weird line or end of block, maybe reset comment?
                # For now, simple logic is fine.
                pass

    return entries


def main():
    entries = parse_blocked_ips()

    ip_list_html = ""
    for entry in entries:
        comment_html = (
            f'<span class="comment">{entry["comment"]}</span>'
            if entry["comment"]
            else ""
        )
        ip_list_html += (
            f'<div class="ip-item"><span>{entry["ip"]}</span>{comment_html}</div>\n'
        )

    html = HTML_TEMPLATE.format(
        count=len(entries), ip_list_html=ip_list_html, generated_at="Latest (Automated)"
    )

    OUTPUT_HTML.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_HTML, "w") as f:
        f.write(html)

    print(f"Generated blocked stats: {len(entries)} IPs -> {OUTPUT_HTML}")

    # Update .env with timestamp
    ENV_FILE = REPO_ROOT / "opt/my-website/.env"
    build_time = datetime.now().isoformat()

    env_content = ""
    if ENV_FILE.exists():
        with open(ENV_FILE, "r") as f:
            env_content = f.read()

    # Regex to replace or append PUBLIC_BLOCKED_UPDATED_AT
    if "PUBLIC_BLOCKED_UPDATED_AT=" in env_content:
        env_content = re.sub(
            r"^PUBLIC_BLOCKED_UPDATED_AT=.*$",
            f"PUBLIC_BLOCKED_UPDATED_AT={build_time}",
            env_content,
            flags=re.MULTILINE,
        )
    else:
        if env_content and not env_content.endswith("\n"):
            env_content += "\n"
        env_content += f"PUBLIC_BLOCKED_UPDATED_AT={build_time}\n"

    with open(ENV_FILE, "w") as f:
        f.write(env_content)
    print(f"Updated .env with PUBLIC_BLOCKED_UPDATED_AT={build_time}")


if __name__ == "__main__":
    main()
