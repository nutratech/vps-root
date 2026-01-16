import os
import klaus
from klaus.contrib.wsgi import make_app

# Root directory for repositories
REPO_ROOT = os.environ.get('KLAUS_REPOS_ROOT', '/srv/git')
SITE_NAME = os.environ.get('KLAUS_SITE_NAME', 'Git Repos')

def find_git_repos(root_dir):
    """
    Recursively find all git repositories (directories ending in .git)
    """
    repos = []
    for root, dirs, files in os.walk(root_dir):
        # Scan directories
        for d in dirs:
            if d.endswith('.git'):
                full_path = os.path.join(root, d)
                repos.append(full_path)
    return sorted(repos)

# Discover repositories
repositories = find_git_repos(REPO_ROOT)

if not repositories:
    print(f"Warning: No repositories found in {REPO_ROOT}")
else:
    print(f"Found {len(repositories)} repositories: {repositories}")

# Create the WSGI application
application = make_app(
    repositories,
    SITE_NAME,
)
