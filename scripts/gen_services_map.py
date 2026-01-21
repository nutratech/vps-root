#!/usr/bin/env python3
import re
import os
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
    </style>
</head>
<body>
    <h1>{title}</h1>
    <p class="meta">Generated automatically from Nginx configuration.</p>

    {content}

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


import sys
import argparse

def get_all_services(custom_config_path=None):
    # Regex to find "Version X: Description" lines
    version_pattern = re.compile(r"^\s*#\s*Version\s+(\w+):\s*(.+)$", re.MULTILINE)
    service_pattern = re.compile(r"^\s*#\s*Service:\s*(.+?)\s*\|\s*(.+)$", re.MULTILINE)

    services_git = parse_file(NGINX_CONF, version_pattern, is_version=True)

    DEFAULT_CONF = None
    if custom_config_path:
        p = Path(custom_config_path)
        if p.exists():
            DEFAULT_CONF = p
            print(f"Using custom config: {DEFAULT_CONF}")
        else:
            print(f"Error: Custom config not found at {p}")
            sys.exit(1)
    else:
        # Locate default.conf fallback (old logic)
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



def generate_html(title, groups):
    """
    groups: list of tuples (header_name, services_list)
    """
    content_html = ""

    for header, services in groups:
        if header:
            content_html += f'<h2 class="group-header">{header}</h2>'
        
        for s in services:
            # Use absolute URL if it starts with http, otherwise relative
            url = s['url']
            content_html += f"""
        <div class="service">
            <h3><a href="{url}">{url}</a></h3>
            <div class="desc">{s['description']}</div>
        </div>"""

    return HTML_TEMPLATE.format(title=title, content=content_html)



def main():
    parser = argparse.ArgumentParser(description="Generate HTML services map from Nginx config")
    parser.add_argument("config_path", nargs="?", help="Path to the Nginx configuration file")
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
    all_groups = [
        ("Core Services", services_other),
        ("Git Services", services_git)
    ]
    
    # Calculate total items
    total_items = sum(len(g[1]) for g in all_groups)
    print(f"Generating Homepage map with {total_items} items...")
    
    home_html = generate_html("All Services", all_groups)
    
    with open(OUTPUT_HTML_HOME, "w") as f:
        f.write(home_html)
    print(f"Generated Homepage map at: {OUTPUT_HTML_HOME}")


if __name__ == "__main__":
    main()

