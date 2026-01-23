Git HTTP & Gitweb Configuration
===============================

This document covers the configuration and maintenance of the Git HTTP backend and Gitweb interface.

Gitweb Owner Display
--------------------

By default, Gitweb displays the filesystem owner of the repository. However, the deployment script (`deploy.sh`) enforces `www-data:www-data` ownership on `/srv/git` for security and access reasons. This causes all repositories to show "www-data" as the owner in the Gitweb interface.

To fix this **without changing file permissions**, you can set the `gitweb.owner` configuration variable inside each repository's `.git/config`. This adheres to the Gitweb configuration precedence and persists even after deployment scripts reset file ownership.

**Command to set owner for all repositories:**

.. code-block:: bash

    sudo find /srv/git -maxdepth 1 -name "*.git" -type d -exec git --git-dir="{}" config gitweb.owner "Shane J" \;

**Why use this method?**

*   **Persistence:** `deploy.sh` resets filesystem permissions to `www-data` on every run. Setting `gitweb.owner` survives this.
*   **Security:** Keeps the web server user (`www-data`) as the file owner, preventing permission errors.
*   **Accuracy:** Allows displaying a human-readable name ("Shane J") instead of a system user.
