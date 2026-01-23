# Gitea Maintenance (Backup & Update)

This document outlines the procedures for backing up and updating the Gitea instance.

## Backup

We use a custom script located on the local machine (e.g., `~/.backups/pg_backups`) to trigger a remote backup and pull the archive.

**Usage:**

```bash
# Run from your local machine
~/.backups/pg_backups/gitea-backup.sh
```

**Configuration:**

You can override the defaults using environment variables:

```bash
HOST="my-gitea.server" SSH_USER="admin" ~/.backups/pg_backups/gitea-backup.sh
```

**Prerequisites (Sudo Access):**

Since the script runs non-interactively, your SSH user must be able to run `gitea` commands as the Gitea user without a password.

On the **Gitea Server**, add this to `/etc/sudoers` (using `sudo visudo`):

```text
# Allow shane to run commands as gg without a password
shane ALL=(gg) NOPASSWD: /usr/local/bin/gitea
```

**What it does:**

1. SSHs into the Gitea server and triggers a dump.
2. Downloads the zip file to your local machine (`~/.backups/pg_backups/gitea/`).
3. **Local Processing:**
    * Unzips the backup.
    * Converts `gitea.db` (SQLite) to `gitea.sql` (Text) for easier version control (requires local `sqlite3`).
    * Compresses large binary folders (`repos`, `data`, `log`) into `assets.tar.xz`.
    * Deletes the extracted binaries to keep the repo clean.

**Resulting Structure:**

* `.gitea-sqlite/app.ini` (Text Config)
* `.gitea-sqlite/gitea.db` (SQLite Database - Handled by `git-sqlite-filter`)
* `.gitea-sqlite/gitea-db.sql` (SQL Dump - Redundant but safe to keep)
* `.gitea-sqlite/custom/` (Templates, Public Assets, Configs - Kept as files)
* `.gitea-sqlite/data/` (Site Data - Kept as files)
* `.gitea-sqlite/log/` (Logs - Kept as files)
* *(Repositories are excluded from this backup)*

## Prerequisites (Sudo Access)

The script uses `gitea-remote-dump.sh` which runs `gitea dump` on the server.
Since Gitea is installed as a binary at `/usr/local/bin/gitea`, ensure your user has sudo execution rights.

**Reducing Backup Size:**
If your backups are large (e.g., hundreds of MBs), it's likely due to **repo-archive**. This folder stores cached zip/tar.gz files generated when users download repository sources.

* **Status:** Safe to delete. They are regenerated on demand.
* **Action:** You can delete them manually or via cron to save space.

### Method 1: Via Gitea Interface (Recommended)

1. Log in as a site administrator.
2. Go to **Site Administration** > **Monitor** (or **Maintenance**).
3. Find **Cron Tasks**.
4. Locate **Delete all repository archives** and click **Run**.

### Method 2: Via CLI

```bash
# On the server
sudo -u gg rm -rf /var/lib/gitea/data/repo-archive/*
```

## Update Procedure

To update Gitea, you replace the binary file.

**Prerequisites:**

* Check the latest version on [Gitea Releases](https://github.com/go-gitea/gitea/releases).
* Ensure you have `sudo` access.

**Steps:**

1. **Stop the Service:**

    ```bash
    sudo systemctl stop gitea
    ```

2. **Backup Current Binary:**

    ```bash
    sudo cp /usr/local/bin/gitea /usr/local/bin/gitea.bak
    ```

3. **Download New Version:**

    Replace `<VERSION>` with the desired version (e.g., `1.21.4`).

    ```bash
    sudo wget -O /usr/local/bin/gitea https://dl.gitea.com/gitea/<VERSION>/gitea-<VERSION>-linux-amd64
    ```

4. **Make Executable:**

    ```bash
    sudo chmod +x /usr/local/bin/gitea
    ```

5. **Restart Service:**

    ```bash
    sudo systemctl start gitea
    ```

6. **Verify:**

    Check the status and logs to ensure it started correctly.

    ```bash
    sudo systemctl status gitea
    ```
