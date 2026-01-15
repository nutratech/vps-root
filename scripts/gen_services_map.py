#!/usr/bin/env python3
import re
import os
from pathlib import Path

# Paths relative to repo root
REPO_ROOT = Path(__file__).parent.parent
NGINX_CONF = REPO_ROOT / "etc/nginx/conf.d/git-http.conf"
OUTPUT_HTML = REPO_ROOT / "scripts/gitweb-simplefrontend/services.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
    <title>NutraTech Git Services</title>
    <style>
        body {{ font-family: sans-serif; max-width: 800px; margin: 2rem auto; line-height: 1.6; padding: 0 1rem; color: #333; }}
        h1 {{ border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }}
        .service {{ margin-bottom: 1.5rem; padding: 1.5rem; border: 1px solid #ddd; border-radius: 8px; background: #f9f9f9; }}
        .service:hover {{ background: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.1); border-color: #ccc; }}
        .service h2 {{ margin-top: 0; margin-bottom: 0.5rem; }}
        .service a {{ text-decoration: none; color: #0066cc; }}
        .service a:hover {{ text-decoration: underline; }}
        .desc {{ margin-bottom: 0.5rem; }}
        .meta {{ font-size: 0.85em; color: #666; }}
        .tag {{ display: inline-block; padding: 2px 8px; background: #e0e0e0; border-radius: 12px; font-size: 0.8em; margin-right: 0.5rem; color: #444; }}
    </style>
</head>
<body>
    <h1>Git Services Map</h1>
    <p class="meta">Generated automatically from Nginx configuration.</p>
    
    {services_html}
    
</body>
</html>"""


def parse_nginx_config():
    services = []

    if not NGINX_CONF.exists():
        print(f"Error: Could not find config at {NGINX_CONF}")
        return []

    # Regex to find "Version X: Description" lines
    # Matches: # Version 1: Original Gitweb (Standard)
    version_pattern = re.compile(r"^\s*#\s*Version\s+(\w+):\s*(.+)$", re.MULTILINE)

    with open(NGINX_CONF, "r") as f:
        content = f.read()

        matches = version_pattern.findall(content)
        for version_id, description in matches:
            # Clean up version ID (e.g., '1' -> 'v1')
            if not version_id.startswith("v"):
                vid = f"v{version_id}"
            else:
                vid = version_id

            services.append(
                {"id": vid, "url": f"/{vid}", "description": description.strip()}
            )

    return services


def generate_html(services):
    services_html = ""

    for s in services:
        services_html += f"""
    <div class="service">
        <h2><a href="{s['url']}">{s['url']}</a></h2>
        <div class="desc">{s['description']}</div>
    </div>"""

    return HTML_TEMPLATE.format(services_html=services_html)


def main():
    print(f"Reading config from: {NGINX_CONF}")
    services = parse_nginx_config()

    if not services:
        print("No services found!")
        return

    print(f"Found {len(services)} services: {[s['id'] for s in services]}")

    html_content = generate_html(services)

    os.makedirs(OUTPUT_HTML.parent, exist_ok=True)
    with open(OUTPUT_HTML, "w") as f:
        f.write(html_content)

    print(f"Generated site map at: {OUTPUT_HTML}")


if __name__ == "__main__":
    main()
