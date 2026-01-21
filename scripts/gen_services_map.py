#!/usr/bin/env python3
import os
import re
from datetime import datetime
from pathlib import Path

# Paths relative to repo root
REPO_ROOT = Path(__file__).parent.parent
NGINX_CONF = REPO_ROOT / "etc/nginx/conf.d/git-http.dev.conf"
OUTPUT_HTML = REPO_ROOT / "scripts/gitweb-simplefrontend/services.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <style>
        body {{ font-family: sans-serif; max-width: 800px; margin: 2rem auto; line-height: 1.6; padding: 0 1rem; color: #333; }}
        h1 {{ border-bottom: 2px solid #eee; padding-bottom: 0.5rem; }}
        h2.group-header {{ margin-top: 2rem; border-bottom: 1px solid #eee; color: #555; }}
        .service {{ margin-bottom: 1.5rem; padding: 1.5rem; border: 1px solid #ddd; border-radius: 8px; background: #f9f9f9; }}
        .service:hover {{ background: #fff; box-shadow: 0 2px 5px rgba(0,0,0,0.1); border-color: #ccc; }}
        .service h3 {{ margin-top: 0; margin-bottom: 0.5rem; font-size: 1.25rem; }}
        .service a {{ text-decoration: none; color: #0066cc; }}
        .service a:hover {{ text-decoration: underline; }}
        .desc {{ margin-bottom: 0.5rem; }}
        .meta {{ font-size: 0.85em; color: #666; }}
        footer {{ margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid #eee; font-size: 0.8em; color: #888; text-align: center; }}
        footer .ssi {{ font-family: monospace; background: #f5f5f5; padding: 0.2em 0.5em; border-radius: 3px; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <p class="meta">Generated automatically from Nginx configuration.</p>

    {content}

    <footer>
        <p>Built: {build_time} | Services: {service_count}</p>
        <p>Nginx: <span class="ssi">v<!--#echo var="nginx_version"--></span> |
           Served: <span class="ssi"><!--#echo var="date_local"--></span> |
           Request: <span class="ssi"><!--#echo var="request_uri"--></span></p>
    </footer>
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

    # Always scan all .conf files in the directory
    if NGINX_CONF_DIR.exists():
        conf_files = list(NGINX_CONF_DIR.glob("*.conf"))
        print(f"Scanning {len(conf_files)} config files in {NGINX_CONF_DIR}...")
    else:
        print(f"Warning: Config directory not found at {NGINX_CONF_DIR}")
        conf_files = []

    services_other = []
    for conf_file in conf_files:
        # Skip the git-http conf as it's parsed separately
        if conf_file.name == "git-http.dev.conf":
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

    # Output 1: Git Services Only
    print(f"Generating Git Services map with {len(services_git)} items...")
    git_groups = [("", services_git)]
    git_html = generate_html("Git Services", git_groups)

    os.makedirs(OUTPUT_HTML.parent, exist_ok=True)
    with open(OUTPUT_HTML, "w") as f:
        f.write(git_html)
    print(f"Generated Git map at: {OUTPUT_HTML}")

    # Output 2: Homepage (All Services)
    OUTPUT_HTML_HOME = REPO_ROOT / "scripts/homepage.html"

    # Grouping logic
    all_groups = [("Core Services", services_other), ("Git Services", services_git)]

    # Calculate total items
    total_items = sum(len(g[1]) for g in all_groups)
    print(f"Generating Homepage map with {total_items} items...")

    # Construction Notice
    construction_notice = """
    <p>The site is under construction/rebuild... all the services are run from two VPS servers, one with 1 GB and another with 2 GB of RAM.</p>
    <p>Please see the services we have online below during our extensive rebuild process (Jan 2026).</p>
    """

    home_html = generate_html(
        "All Services", all_groups, intro_html=construction_notice
    )

    with open(OUTPUT_HTML_HOME, "w") as f:
        f.write(home_html)
    print(f"Generated Homepage map at: {OUTPUT_HTML_HOME}")


if __name__ == "__main__":
    main()
