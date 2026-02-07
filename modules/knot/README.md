# GitHub ↔ Tangled Sync

Tools for syncing repositories between GitHub and Tangled.

## Components

### 1. GitHub → Tangled Sync Service (`github-sync.nix`)

Automatically mirrors public GitHub repositories to Tangled on a schedule.

**Features:**
- Nightly sync of all public repos
- Automatically pulls from GitHub and pushes to Tangled
- Handles new repos once they're created on Tangled

**Configuration:**

```nix
{
  jsp.services.github-tangled-sync = {
    enable = true;
    githubUsername = "jaspermayone";
    tangledHandle = "jaspermayone.tngl.sh";
    tangledKnot = "knot.jaspermayone.com";
    secretsFile = "/path/to/secrets"; # Should contain GITHUB_TOKEN
    interval = "daily"; # or "hourly", "weekly", etc.
  };
}
```

### 2. Tangled → GitHub Sync Service (`sync.nix`)

Mirrors repositories from Tangled/Knot to GitHub (opposite direction).

**Use case:** When Tangled is your primary development platform

### 3. `projn` - New Project Creator

CLI tool to create a project on both GitHub and Tangled simultaneously.

**Usage:**

```bash
projn my-awesome-project "An awesome new project"
```

**What it does:**
1. Creates a local directory with initialized git repo
2. Creates a GitHub repository
3. Creates a Tangled repository (requires manual creation for now)
4. Adds both remotes (origin → GitHub, tangled → Tangled)
5. Creates initial README
6. Pushes to both platforms

**Environment variables:**
- `GITHUB_USERNAME` - GitHub username (default: jaspermayone)
- `TANGLED_HANDLE` - Tangled handle (default: jaspermayone.tngl.sh)
- `TANGLED_KNOT` - Tangled knot server (default: knot.jaspermayone.com)
- `PROJECTS_DIR` - Base directory for projects (default: ~/projects)

## Initial Setup

### Step 1: Create Tangled Repos for Existing GitHub Repos

Since XRPC API authentication is still being implemented, use the interactive script:

```bash
./scripts/init-tangled-sync.sh
```

This script will:
1. List all your public GitHub repos
2. Guide you through creating each one on Tangled
3. Automatically sync the content once created

### Step 2: Enable Nightly Sync

Add to your NixOS/nix-darwin configuration:

```nix
{
  imports = [
    ./modules/knot/github-sync.nix
  ];

  jsp.services.github-tangled-sync = {
    enable = true;
    secretsFile = config.age.secrets.github-token.path; # or your secrets setup
  };
}
```

### Step 3: Create Secrets File

The sync service needs a GitHub token. Create a secrets file with:

```bash
GITHUB_TOKEN=ghp_your_token_here
```

Or use agenix/sops-nix for encrypted secrets.

## Usage

### Creating a New Project

```bash
# Create a new project
projn my-new-project "My cool new project"

# Creates:
# - ~/projects/my-new-project/ (local directory)
# - https://github.com/jaspermayone/my-new-project
# - https://tangled.org/jaspermayone.tngl.sh/my-new-project
```

### Pushing to Both Platforms

```bash
# Push to GitHub
git push origin main

# Push to Tangled
git push tangled main

# Push to both at once
git push origin tangled main

# Or configure git to push to both by default
git config remote.pushdefault origin
git remote set-url --add --push origin $(git remote get-url origin)
git remote set-url --add --push origin $(git remote get-url tangled)
```

### Manual Sync

If you need to manually sync repos outside the nightly schedule:

```bash
# On the machine with the sync service
sudo systemctl start github-tangled-sync.service

# Check logs
sudo journalctl -u github-tangled-sync.service -f
```

## Future Improvements

- [ ] Implement XRPC API authentication for automatic Tangled repo creation
- [ ] Add GitHub webhook handler for instant syncing on push
- [ ] Support for repo deletion/archival sync
- [ ] Bidirectional sync (detect changes on either side)
- [ ] Support for private repos (with proper secrets management)

## Architecture

```
┌─────────────────┐
│     GitHub      │
│  (Source)       │
└────────┬────────┘
         │
         │ gh CLI
         ▼
┌─────────────────┐
│  Sync Service   │
│  (NixOS/Darwin) │
└────────┬────────┘
         │
         │ git push
         ▼
┌─────────────────┐
│    Tangled      │
│  (knot.*)       │
└─────────────────┘
```

## Troubleshooting

### "Permission denied" when pushing to Tangled

Make sure your SSH key is added to Tangled:
1. Go to https://tangled.org
2. Settings → Keys
3. Add your public SSH key

### Repo doesn't exist on Tangled

The sync service only syncs existing repos. Create the repo on Tangled first:
1. Visit https://tangled.org
2. Click '+' → 'repository'
3. Fill in details (name must match GitHub repo name)
4. Select your knot server

### Sync service not running

Check the systemd timer:
```bash
sudo systemctl status github-tangled-sync.timer
sudo systemctl start github-tangled-sync.timer
```

Check the service logs:
```bash
sudo journalctl -u github-tangled-sync.service
```
