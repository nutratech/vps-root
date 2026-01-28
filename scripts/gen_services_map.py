#!/usr/bin/env python3
import os
import re
from datetime import datetime
from pathlib import Path

# Paths relative to repo root
REPO_ROOT = Path(__file__).parent.parent
NGINX_CONF = REPO_ROOT / "etc/nginx/conf.d/dev/git-http.conf"
OUTPUT_HTML = REPO_ROOT / "scripts/gitweb-simplefrontend/services.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <style>
        body {{ font-family: sans-serif; max-width: 800px; margin: 2rem auto; line-height: 1.6; padding: 0 1rem; color: #e0e0e0; background: #1a1a2e; }}
        h1 {{ border-bottom: 2px solid #333; padding-bottom: 0.5rem; color: #fff; }}
        h2.group-header {{ margin-top: 2rem; border-bottom: 1px solid #333; color: #aaa; }}
        .service {{ margin-bottom: 1.5rem; padding: 1.5rem; border: 1px solid #333; border-radius: 8px; background: #16213e; }}
        .service:hover {{ background: #1f3460; box-shadow: 0 2px 8px rgba(0,0,0,0.4); border-color: #4a5568; }}
        .service h3 {{ margin-top: 0; margin-bottom: 0.5rem; font-size: 1.25rem; }}
        .service a {{ text-decoration: none; color: #60a5fa; }}
        .service a:hover {{ text-decoration: underline; color: #93c5fd; }}
        .desc {{ margin-bottom: 0.5rem; color: #b0b0b0; }}
        .meta {{ font-size: 0.85em; color: #888; }}
        footer {{ margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid #333; font-size: 0.8em; color: #666; text-align: center; }}
        footer .ssi {{ font-family: monospace; background: #2d3748; padding: 0.2em 0.5em; border-radius: 3px; color: #a0aec0; }}
        footer a {{ color: #93c5fd; }}
        footer a:hover {{ color: #bfdbfe; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <p class="meta">Generated automatically from Nginx configuration.</p>

    {content}

    <footer>
        <p>Built: {build_time} | Services: {service_count} | Server: San Jose, CA</p>
        <p>Nginx: <span class="ssi">v<!--#echo var="nginx_version"--></span> |
           Protocol: <span class="ssi"><!--#echo var="server_protocol"--></span> |
           Served: <span class="ssi"><!--#echo var="date_local"--></span> |
           Latency: <span id="latency" class="ssi">...</span></p>
        <p>Hosted with love thanks to <a href="https://heliohost.org" target="_blank">HelioHost</a></p>
    </footer>
    <script>
    (function() {{
        // IE11-compatible: use performance.timing (deprecated but widely supported)
        var timing = window.performance && window.performance.timing;
        if (timing) {{
            window.onload = function() {{
                var latency = timing.responseEnd - timing.requestStart;
                var el = document.getElementById('latency');
                if (el) el.textContent = latency + 'ms';
            }};
        }}
    }})();
    </script>
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
            items.append(
                {"id": vid, "url": f"/{vid}", "description": description.strip()}
            )
        else:
            name, url = m
            items.append(
                {"id": name.strip(), "url": url.strip(), "description": name.strip()}
            )
    return items


import argparse
import sys


def get_all_services(custom_config_path=None):
    # Regex to find "Version X: Description" lines
    version_pattern = re.compile(r"^\s*#\s*Version\s+(\w+):\s*(.+)$", re.MULTILINE)
    service_pattern = re.compile(r"^\s*#\s*Service:\s*(.+?)\s*\|\s*(.+)$", re.MULTILINE)

    services_git = parse_file(NGINX_CONF, version_pattern, is_version=True)

    NGINX_CONF_DIR = REPO_ROOT / "etc/nginx/conf.d"

    # Use custom path if provided, otherwise scan all .conf files
    if custom_config_path:
        path = Path(custom_config_path)
        if path.is_dir():
            conf_files = list(path.rglob("*.conf"))
            print(f"Scanning custom directory: {path} ({len(conf_files)} files)")
        elif path.exists():
            conf_files = [path]
            print(f"Using custom config file: {path}")
        else:
            print(f"Warning: Custom config not found at {path}")
            conf_files = []
    elif NGINX_CONF_DIR.exists():
        conf_files = list(NGINX_CONF_DIR.rglob("*.conf"))
        print(f"Scanning {len(conf_files)} config files in {NGINX_CONF_DIR}...")
    else:
        print(f"Warning: Config directory not found at {NGINX_CONF_DIR}")
        conf_files = []

    services_other = []
    for conf_file in conf_files:
        # Skip the git-http conf as it's parsed separately
        if conf_file.name in ["git-http.conf", "git-http.dev.conf"]:
            continue

        print(f"  Parsing {conf_file.name}...")
        services_other.extend(parse_file(conf_file, service_pattern, is_version=False))

    # Sort services by ID for consistent output
    services_other.sort(key=lambda x: x["id"])

    return services_git, services_other


def generate_html(title, groups, intro_html=None):
    """
    groups: list of tuples (header_name, services_list)
    intro_html: optional HTML string to insert before groups
    """
    content_html = ""

    if intro_html:
        content_html += f'<div class="intro">{intro_html}</div>'

    for header, services in groups:
        if header:
            content_html += f'<h2 class="group-header">{header}</h2>'

        for s in services:
            # Use absolute URL if it starts with http, otherwise relative
            url = s["url"]
            content_html += f"""
        <div class="service">
            <h3><a href="{url}">{url}</a></h3>
            <div class="desc">{s['description']}</div>
        </div>"""

    return HTML_TEMPLATE.format(
        title=title,
        content=content_html,
        build_time=datetime.now().strftime("%Y-%m-%d %H:%M:%S %Z"),
        service_count=sum(len(g[1]) for g in groups),
    )


def main():
    parser = argparse.ArgumentParser(
        description="Generate HTML services map from Nginx config"
    )
    parser.add_argument(
        "config_path", nargs="?", help="Path to the Nginx configuration file"
    )
    args = parser.parse_args()

    print(f"Reading configs...")
    services_git, services_other = get_all_services(args.config_path)

    # Prefix Git services with the correct domain
    for s in services_git:
        if s["url"].startswith("/"):
            s["url"] = f"https://git.nutra.tk{s['url']}"

    # Output 2: Homepage (All Services)
    OUTPUT_HTML_HOME = REPO_ROOT / "scripts/homepage.html"

    # Grouping logic
    all_groups = [("Core Services", services_other), ("Git Services", services_git)]

    # Calculate total items
    total_items = sum(len(g[1]) for g in all_groups)

    # Construction Notice
    construction_notice = """
    <p>The site is under construction/rebuild... all the services are run from two VPS servers, one with 1 GB and another with 2 GB of RAM.</p>
    <p>Please see the services we have online below during our extensive rebuild process (Jan 2026).</p>
    """

    home_html = generate_html(
        "Nutratech | All Services", all_groups, intro_html=construction_notice
    )

    print(f"Generating Unified Service Map with {total_items} items...")

    # Write to Homepage
    with open(OUTPUT_HTML_HOME, "w") as f:
        f.write(home_html)
    print(f"Generated Homepage map at: {OUTPUT_HTML_HOME}")

    # Write to Git Services (same content)
    os.makedirs(OUTPUT_HTML.parent, exist_ok=True)
    with open(OUTPUT_HTML, "w") as f:
        f.write(home_html)
    print(f"Generated Git map at: {OUTPUT_HTML}")

    # Output 3: JSON Data for Svelte App
    # We want to output this to opt/my-website/src/lib/services.json
    OUTPUT_JSON = REPO_ROOT / "opt/my-website/src/lib/services.json"
    import json

    # Flatten groups for JSON
    json_data = {
        "generated_at": datetime.now().isoformat(),
        "groups": [
            {"name": name, "services": services} for name, services in all_groups
        ],
    }

    os.makedirs(OUTPUT_JSON.parent, exist_ok=True)
    with open(OUTPUT_JSON, "w") as f:
        json.dump(json_data, f, indent=2)
    print(f"Generated JSON data at: {OUTPUT_JSON}")


if __name__ == "__main__":
    main()
