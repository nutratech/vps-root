#!/usr/bin/env python3
import argparse
import json
import os
import shlex
import subprocess
import sys

try:
    import argcomplete
except ImportError:
    argcomplete = None

# paths
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
# REPO_JSON is expected to be in the same dir as the script
REPO_JSON = os.path.join(SCRIPT_DIR, "repos.json")
REPO_CSV = os.path.join(SCRIPT_DIR, "repo_metadata.csv")
GIT_ROOT = "/srv/git"


def load_repos():
    if os.path.exists(REPO_JSON):
        with open(REPO_JSON, "r") as f:
            try:
                return json.load(f)
            except json.JSONDecodeError:
                print(f"Warning: {REPO_JSON} is invalid JSON. Returning empty.")
                return {}
    return {}


def save_repos(data):
    with open(REPO_JSON, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


def remote_exists(remote, path):
    if remote:
        cmd = ["ssh", remote, f"test -e {shlex.quote(path)}"]
        return subprocess.call(cmd) == 0
    else:
        return os.path.exists(path)


def remote_isdir(remote, path):
    if remote:
        cmd = ["ssh", remote, f"test -d {shlex.quote(path)}"]
        return subprocess.call(cmd) == 0
    else:
        return os.path.isdir(path)


def remote_makedirs(remote, path):
    if remote:
        subprocess.check_call(["ssh", remote, f"mkdir -p {shlex.quote(path)}"])
    else:
        os.makedirs(path, exist_ok=True)


def remote_run(remote, cmd_list, check=True):
    if remote:
        cmd_str = " ".join(shlex.quote(c) for c in cmd_list)
        subprocess.check_call(["ssh", remote, cmd_str])
    else:
        subprocess.run(cmd_list, check=check)


def remote_write(remote, path, content):
    if remote:
        # Use simple cat redirection
        p = subprocess.Popen(
            ["ssh", remote, f"cat > {shlex.quote(path)}"], stdin=subprocess.PIPE
        )
        p.communicate(input=content.encode("utf-8"))
        if p.returncode != 0:
            raise subprocess.CalledProcessError(p.returncode, "remote write")
    else:
        with open(path, "w") as f:
            f.write(content)


def normalize_repo_path(name):
    """Ensures path ends in .git and usually has a projects/ prefix if simplistic."""
    # Logic: If it has slashes, trust the user. If not, prepend projects/.
    # Always append .git if missing.
    name = name.strip()
    if "/" not in name:
        name = f"projects/{name}"
    if not name.endswith(".git"):
        name += ".git"
    return name


def get_current_dir_name():
    return os.path.basename(os.getcwd())


# ----------------- Commands -----------------


def cmd_add_clone(args, remote):
    url = args.url
    data = load_repos()

    # Determine repo name
    if args.name:
        repo_name = args.name
    else:
        repo_name = url.rstrip("/").rsplit("/", 1)[-1]
        if repo_name.endswith(".git"):
            repo_name = repo_name[:-4]

    repo_rel_path = normalize_repo_path(repo_name)
    full_path = os.path.join(GIT_ROOT, repo_rel_path)

    print(f"Adding Clone: {url}")
    print(f"Target: {full_path} (Remote: {remote if remote else 'Local'})")

    # Create parent dir
    parent_dir = os.path.dirname(full_path)
    if not remote_exists(remote, parent_dir):
        remote_makedirs(remote, parent_dir)

    # Clone
    if not remote_exists(remote, full_path):
        print(f"Cloning into {full_path}...")
        remote_run(remote, ["git", "clone", "--mirror", url, full_path])
    else:
        print("Repository already exists. Updating metadata...")

    # Configure
    configure_repo(
        remote,
        repo_rel_path,
        full_path,
        args.desc,
        args.owner,
        origin_url=url,
        data=data,
    )


def cmd_init(args, remote):
    data = load_repos()

    name = args.name
    if not name:
        # Try to infer from current directory
        name = get_current_dir_name()

    repo_rel_path = normalize_repo_path(name)
    full_path = os.path.join(GIT_ROOT, repo_rel_path)

    print(f"Initializing empty repo: {repo_rel_path}")
    print(f"Target: {full_path} (Remote: {remote if remote else 'Local'})")

    # Mkdir
    remote_makedirs(remote, full_path)

    # Git Init
    remote_run(remote, ["git", "-C", full_path, "init", "--bare"])

    # Daemon ok
    # We can use remote_run with touch, or remote_write.
    # touch is simpler.
    remote_run(remote, ["touch", os.path.join(full_path, "git-daemon-export-ok")])

    # Safe Directory
    # We need to run this globally or on the system level, but running it locally for the user often works
    # if the user accessing it is the one running this.
    # However, 'git config --global' on remote affects the remote user (git).
    remote_run(
        remote, ["git", "config", "--global", "--add", "safe.directory", full_path]
    )

    # Configure
    configure_repo(remote, repo_rel_path, full_path, args.desc, args.owner, data=data)

    # Auto Remote (Local side)
    if args.auto_remote:
        # Check if we are in a git repo
        if os.path.exists(".git"):
            remote_url = (
                f"ssh://{remote}/{full_path.lstrip('/')}" if remote else full_path
            )
            remote_name = "helio-web"  # standardizing on this name from makefile?

            print(f"Configuring local remote '{remote_name}' -> {remote_url}")
            # Try adding, if fails, try setting
            res = subprocess.call(
                ["git", "remote", "add", remote_name, remote_url],
                stderr=subprocess.DEVNULL,
            )
            if res != 0:
                print(f"Remote '{remote_name}' exists, setting url...")
                subprocess.call(["git", "remote", "set-url", remote_name, remote_url])

            print("You can now push: git push -u helio-web main")


def cmd_rename(args, remote):
    data = load_repos()

    old_rel = normalize_repo_path(args.old)
    new_rel = normalize_repo_path(args.new)

    old_full = os.path.join(GIT_ROOT, old_rel)
    new_full = os.path.join(GIT_ROOT, new_rel)

    print(f"Renaming {old_rel} -> {new_rel}")

    if not remote_exists(remote, old_full):
        print(f"Error: Source repo {old_rel} does not exist.")
        sys.exit(1)

    if remote_exists(remote, new_full):
        print(f"Error: Destination repo {new_rel} already exists.")
        sys.exit(1)

    # Create new parent
    remote_makedirs(remote, os.path.dirname(new_full))

    # Move
    remote_run(remote, ["mv", old_full, new_full])

    # Update Json
    if old_rel in data:
        data[new_rel] = data.pop(old_rel)
        save_repos(data)
        print("Updated local repos.json")
    else:
        print(f"Warning: {old_rel} was not found in repos.json. No metadata moved.")

    # Safe Directory for new path
    remote_run(
        remote, ["git", "config", "--global", "--add", "safe.directory", new_full]
    )

    print(f"Success. Check your local remotes if you were pushing to {old_rel}.")


def cmd_update(args, remote):
    data = load_repos()

    target = args.name
    if target:
        # Update/configure single
        repo_rel_path = normalize_repo_path(target)
        full_path = os.path.join(GIT_ROOT, repo_rel_path)

        if not remote_exists(remote, full_path):
            print(f"Warning: {repo_rel_path} does not exist on remote. Skipping.")
            return

        configure_repo(
            remote,
            repo_rel_path,
            full_path,
            args.desc,
            args.owner,
            origin_url=args.origin,
            data=data,
        )
    else:
        print("Error: Name required.")


def repo_completer(prefix, parsed_args, **kwargs):
    # Load repos for completion
    data = load_repos()
    return [k for k in data.keys() if k.startswith(prefix)]


def cmd_sync(args, remote):
    if not remote:
        print("Error: --remote is required for sync (or set VPS_REMOTE env var)")
        sys.exit(1)

    print(f"Scanning {remote}:{GIT_ROOT}...")

    # Remote python script to gather all metadata in one go
    remote_script = f"""
import os, json, subprocess

root = "{GIT_ROOT}"
results = {{}}

for dirpath, dirnames, filenames in os.walk(root):
    for d in dirnames:
        if d.endswith('.git'):
            full_path = os.path.join(dirpath, d)
            rel_path = os.path.relpath(full_path, root)
            
            # Get description
            desc = ""
            desc_file = os.path.join(full_path, 'description')
            if os.path.exists(desc_file):
                try:
                    with open(desc_file, 'r') as f:
                        desc = f.read().strip()
                        if "Unnamed repository" in desc: desc = ""
                except: pass
            
            # Get owner/origin via git config
            owner = ""
            origin = ""
            try:
                # We use git config to read keys. 
                # Note: 'git config' might fail if safe.directory issues, but usually fine for reading files directly if we parse?
                # Safer to use git command.
                # Only run if directory seems valid.
                cmd = ['git', 'config', '--file', os.path.join(full_path, 'config'), '--list']
                out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL, universal_newlines=True)
                for line in out.splitlines():
                    if line.startswith('gitweb.owner='):
                        owner = line.split('=', 1)[1]
                    if line.startswith('remote.origin.url='):
                        origin = line.split('=', 1)[1]
            except:
                pass
                
            results[rel_path] = {{
                'description': desc,
                'owner': owner,
                'remotes': {{'origin': origin}} if origin else {{}}
            }}
            
print(json.dumps(results))
"""

    # Run the script remotely via SSH
    cmd = ["ssh", remote, "python3", "-c", shlex.quote(remote_script)]

    try:
        output = subprocess.check_output(cmd, universal_newlines=True)
        remote_data = json.loads(output)
    except subprocess.CalledProcessError as e:
        print(f"Error executing remote fetch: {e}")
        return
    except json.JSONDecodeError as e:
        print(f"Error parsing remote response: {e}")
        print("Raw output:", output)
        return

    # Update local data
    data = load_repos()
    updated_count = 0
    new_count = 0

    for rel_path, info in remote_data.items():
        if rel_path not in data:
            data[rel_path] = {}
            new_count += 1
            print(f"  [NEW] Found {rel_path}")
        else:
            updated_count += 1

        data[rel_path]["description"] = info["description"]
        data[rel_path]["owner"] = info["owner"]
        if info.get("remotes"):
            if "remotes" not in data[rel_path]:
                data[rel_path]["remotes"] = {}
            data[rel_path]["remotes"].update(info["remotes"])

    save_repos(data)
    print(
        f"\nSync complete. Added {new_count}, Scanned {updated_count}. (Single SSH connection used)"
    )


def cmd_list(args, remote):
    data = migrate_csv_if_needed()
    print(json.dumps(data, indent=2))


# ----------------- Helpers -----------------


def configure_repo(
    remote, repo_rel_path, full_path, description, owner, origin_url=None, data=None
):
    if data is None:
        data = {}

    msg_parts = []

    # Description
    if description:
        desc_path = os.path.join(full_path, "description")
        remote_write(remote, desc_path, description + "\n")
        msg_parts.append("description")

    # Owner
    if owner:
        config_path = os.path.join(full_path, "config")
        remote_run(
            remote, ["git", "config", "--file", config_path, "gitweb.owner", owner]
        )
        msg_parts.append("owner")

    # JSON Metadata
    if repo_rel_path not in data:
        data[repo_rel_path] = {}

    if description:
        data[repo_rel_path]["description"] = description
    if owner:
        data[repo_rel_path]["owner"] = owner

    if origin_url:
        if "remotes" not in data[repo_rel_path]:
            data[repo_rel_path]["remotes"] = {}
        data[repo_rel_path]["remotes"]["origin"] = origin_url

        # Also update on remote if possible
        try:
            config_path = os.path.join(full_path, "config")
            # check if remote exists
            # It's hard to know if 'origin' exists in the config without checking,
            # but we can just try setting it.
            # If it doesn't exist, we might need to add it? Bare repos don't usually have remotes unless mirrored.
            # Let's try setting.
            remote_run(
                remote,
                [
                    "git",
                    "config",
                    "--file",
                    config_path,
                    "remote.origin.url",
                    origin_url,
                ],
                check=False,
            )
            # Also ensure fetch is set? (Optional, usually implied or not needed for just tracking URL)
        except Exception:
            pass

    # Always save!
    save_repos(data)
    print(f"Configuration updated ({', '.join(msg_parts)}) and saved to repos.json")


def migrate_csv_if_needed():
    """Migrate data from CSV to JSON if JSON is empty/missing and CSV exists."""
    data = load_repos()
    if data:
        return data

    if not os.path.exists(REPO_CSV):
        return data

    print(f"Migrating existing metadata from {REPO_CSV} to {REPO_JSON}...")
    with open(REPO_CSV, "r") as f:
        reader = csv.DictReader(f)
        reader.fieldnames = [name.strip() for name in reader.fieldnames]

        for row in reader:
            path = row.get("repo_path", "").strip()
            if not path:
                continue

            if path not in data:
                data[path] = {
                    "owner": row.get("owner", "").strip(),
                    "description": row.get("description", "").strip(),
                    "remotes": {},
                }

    # We skip the complex remote scanning for now to keep it fast
    save_repos(data)
    return data


# ----------------- Main -----------------


def main():
    parser = argparse.ArgumentParser(
        description="Manage git repos in /srv/git and track metadata"
    )
    parser.add_argument(
        "--remote",
        help="SSH remote (e.g. gg@dev.nutra.tk) or blank for local (env: VPS_REMOTE)",
        default=os.environ.get("VPS_REMOTE"),
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    # ADD
    p_add = subparsers.add_parser("add", help="Clone existin repo")
    p_add.add_argument("url", help="Git clone URL")
    p_add.add_argument("--name", help="Repository name (e.g. 'cli' or 'projects/cli')")
    p_add.add_argument("--desc", help="Description for gitweb", default="")
    p_add.add_argument("--owner", help="Owner for gitweb", default="Shane")
    p_add.set_defaults(func=cmd_add_clone)

    # INIT
    p_init = subparsers.add_parser("init", help="Initialize new bare repo")
    p_init.add_argument(
        "--name",
        help="Repository name (e.g. 'cli' or 'projects/cli'). Defaults to current dir name.",
    )
    p_init.add_argument("--desc", help="Description for gitweb", default="")
    p_init.add_argument("--owner", help="Owner for gitweb", default="Shane")
    p_init.add_argument(
        "--auto-remote",
        action="store_true",
        help="Add this as a remote to current git repo",
    )
    p_init.set_defaults(func=cmd_init)

    # RENAME
    p_mv = subparsers.add_parser("rename", help="Rename/Move repository")
    p_mv.add_argument("old", help="Old path")
    p_mv.add_argument("new", help="New path")
    p_mv.set_defaults(func=cmd_rename)

    # UPDATE
    p_up = subparsers.add_parser("update", help="Update metadata")
    p_up.add_argument("name", help="Repository name").completer = repo_completer
    p_up.add_argument("--desc", help="Description for gitweb")
    p_up.add_argument("--owner", help="Owner for gitweb")
    p_up.add_argument("--origin", help="Update upstream origin URL")
    p_up.set_defaults(func=cmd_update)

    # LIST
    p_list = subparsers.add_parser("list", help="List tracked repositories")
    p_list.set_defaults(func=cmd_list)

    # MIGRATE
    p_mig = subparsers.add_parser("migrate", help="Force migration from CSV")
    p_mig.set_defaults(func=lambda args, r: migrate_csv_if_needed())

    # SYNC
    p_sync = subparsers.add_parser(
        "sync", help="Sync/Import remote repositories to local JSON"
    )
    p_sync.set_defaults(func=cmd_sync)

    if argcomplete:
        argcomplete.autocomplete(parser)

    args = parser.parse_args()

    # Migration check before any command?
    # Or just let them run. load_repos handles empty json nicely.

    if hasattr(args, "func"):
        args.func(args, args.remote)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
