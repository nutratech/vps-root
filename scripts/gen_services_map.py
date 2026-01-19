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



def parse_file(path, pattern, is_version=False):
    if not path.exists():
         print(f"Warning: Could not find config at {path}")
         return []
    
    with open(path, "r") as f:
        content = f.read()

    items = []
    matches = pattern.findall(content)
    for m in matches:
        if is_version:
            version_id, description = m
            # Clean up version ID (e.g., '1' -> 'v1')
            if not version_id.startswith("v"):
                vid = f"v{version_id}"
            else:
                vid = version_id
            items.append({"id": vid, "url": f"/{vid}", "description": description.strip()})
        else:
            name, url = m
            items.append({"id": name.strip(), "url": url.strip(), "description": name.strip()})
    return items


def get_all_services():
    # Regex to find "Version X: Description" lines
    version_pattern = re.compile(r"^\s*#\s*Version\s+(\w+):\s*(.+)$", re.MULTILINE)
    service_pattern = re.compile(r"^\s*#\s*Service:\s*(.+?)\s*\|\s*(.+)$", re.MULTILINE)

    services_git = parse_file(NGINX_CONF, version_pattern, is_version=True)
    
    # Locate default.conf
    # On Server: Read the live deployed config
    live_default = Path("/etc/nginx/conf.d/default.conf")
    # On Local: Read default.dev.conf
    local_dev = REPO_ROOT / "etc/nginx/conf.d/default.dev.conf"
    
    if live_default.exists():
        DEFAULT_CONF = live_default
        print(f"Using live config: {DEFAULT_CONF}")
    else:
        DEFAULT_CONF = local_dev
        print(f"Using local config: {DEFAULT_CONF}")

    services_other = parse_file(DEFAULT_CONF, service_pattern, is_version=False)

    return services_git, services_other


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
    print(f"Reading configs...")
    services_git, services_other = get_all_services()

    # Output 1: Git Services Only
    print(f"Generating Git Services map with {len(services_git)} items...")
    git_html = generate_html(services_git)
    os.makedirs(OUTPUT_HTML.parent, exist_ok=True)
    with open(OUTPUT_HTML, "w") as f:
        f.write(git_html)
    print(f"Generated Git map at: {OUTPUT_HTML}")

    # Output 2: Homepage (All Services)
    # Save to scripts/homepage.html to keep it separate from gitweb assets
    OUTPUT_HTML_HOME = REPO_ROOT / "scripts/homepage.html"
    services_all = services_git + services_other
    print(f"Generating Homepage map with {len(services_all)} items...")
    home_html = generate_html(services_all)
    with open(OUTPUT_HTML_HOME, "w") as f:
        f.write(home_html)
    print(f"Generated Homepage map at: {OUTPUT_HTML_HOME}")


if __name__ == "__main__":
    main()
