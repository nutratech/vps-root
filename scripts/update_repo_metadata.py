#!/usr/bin/env python3
import csv
import os
import subprocess
import sys

# Default to repo_metadata.csv in the current directory if not provided
CSV_FILE = sys.argv[1] if len(sys.argv) > 1 else "repo_metadata.csv"
GIT_ROOT = "/srv/git"


def main():
    if not os.path.exists(CSV_FILE):
        print(f"Error: CSV file '{CSV_FILE}' not found.")
        sys.exit(1)

    print(f"Reading metadata from {CSV_FILE}...")

    with open(CSV_FILE, mode="r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)

        # Normalize column names (strip whitespace)
        reader.fieldnames = [name.strip() for name in reader.fieldnames]

        if "repo_path" not in reader.fieldnames:
            print("Error: CSV must have a 'repo_path' column.")
            sys.exit(1)

        for row in reader:
            repo_rel_path = row["repo_path"].strip()
            owner = row.get("owner", "").strip()
            description = row.get("description", "").strip()

            if not repo_rel_path:
                continue

            full_repo_path = os.path.join(GIT_ROOT, repo_rel_path)

            if not os.path.isdir(full_repo_path):
                print(
                    f"Skipping {repo_rel_path}: Not found directly at {full_repo_path}"
                )
                # Try prepending projects/ if not present, just in case user omitted it
                if not repo_rel_path.startswith("projects/"):
                    alt_path = os.path.join(GIT_ROOT, "projects", repo_rel_path)
                    if os.path.isdir(alt_path):
                        full_repo_path = alt_path
                        print(f"Found at {full_repo_path}")
                    else:
                        continue
                else:
                    continue

            print(f"Updating {repo_rel_path}...")

            # 1. Set Owner (git config gitweb.owner)
            if owner:
                config_file = os.path.join(full_repo_path, "config")
                if os.path.exists(config_file):
                    try:
                        subprocess.run(
                            [
                                "git",
                                "config",
                                "--file",
                                config_file,
                                "gitweb.owner",
                                owner,
                            ],
                            check=True,
                        )
                        print(f"  - Owner set to: {owner}")
                    except subprocess.CalledProcessError as e:
                        print(f"  - Failed to set owner: {e}")
                else:
                    print(f"  - Warning: No config file found at {config_file}")

            # 2. Set Description (write to description file)
            if description:
                desc_file = os.path.join(full_repo_path, "description")
                try:
                    with open(desc_file, "w", encoding="utf-8") as df:
                        df.write(description + "\n")
                    print(f"  - Description updated.")
                except Exception as e:
                    print(f"  - Failed to write description: {e}")

    print("Done.")


if __name__ == "__main__":
    main()
