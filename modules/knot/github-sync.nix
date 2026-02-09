# GitHub to Tangled sync service
# Automatically mirrors public GitHub repositories to Tangled
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.jsp.services.github-tangled-sync;
in
{
  options.jsp.services.github-tangled-sync = {
    enable = lib.mkEnableOption "GitHub to Tangled sync service";

    githubUsername = lib.mkOption {
      type = lib.types.str;
      default = "jaspermayone";
      description = "GitHub username to sync repos from";
    };

    tangledHandle = lib.mkOption {
      type = lib.types.str;
      default = "jaspermayone.tngl.sh";
      description = "Tangled handle (e.g., user.tngl.sh)";
    };

    tangledRepoPath = lib.mkOption {
      type = lib.types.str;
      default = "jaspermayone.com";
      description = "Tangled repository path (e.g., user.com or user.tngl.sh)";
    };

    tangledKnot = lib.mkOption {
      type = lib.types.str;
      default = "knot.jaspermayone.com";
      description = "Tangled knot server to create repos on";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to secrets file containing GITHUB_TOKEN and TANGLED_TOKEN";
    };

    workDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/github-tangled-sync";
      description = "Working directory for git operations";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/log/github-tangled-sync.log";
      description = "Log file location";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Systemd timer interval (default: daily)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.github-tangled-sync = {
      description = "Sync GitHub repositories to Tangled";
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = cfg.secretsFile;
        WorkingDirectory = cfg.workDir;
        ExecStart = pkgs.writeShellScript "github-tangled-sync" ''
          set -euo pipefail

          # Variables
          GITHUB_USERNAME="${cfg.githubUsername}"
          TANGLED_HANDLE="${cfg.tangledHandle}"
          TANGLED_REPO_PATH="${cfg.tangledRepoPath}"
          TANGLED_KNOT="${cfg.tangledKnot}"
          WORK_DIR="${cfg.workDir}"
          LOG_FILE="${cfg.logFile}"

          # Log function
          log() { echo "$(date +'%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"; }

          # Ensure work directory exists
          mkdir -p "$WORK_DIR"

          log "Starting GitHub to Tangled sync for $GITHUB_USERNAME"

          # Get list of public GitHub repos
          REPOS=$(${pkgs.gh}/bin/gh repo list "$GITHUB_USERNAME" \
            --source \
            --no-archived \
            --visibility public \
            --limit 1000 \
            --json name,url,defaultBranchRef \
            --jq '.[] | "\(.name)|\(.url)|\(.defaultBranchRef.name)"')

          if [ -z "$REPOS" ]; then
            log "No public repositories found"
            exit 0
          fi

          SYNCED=0
          FAILED=0

          while IFS='|' read -r repo_name repo_url default_branch; do
            log "Processing: $repo_name"

            REPO_DIR="$WORK_DIR/$repo_name"

            # Clone or update local copy
            if [ ! -d "$REPO_DIR" ]; then
              log "  Cloning $repo_name..."
              if ${pkgs.git}/bin/git clone "$repo_url" "$REPO_DIR" >> "$LOG_FILE" 2>&1; then
                log "  ✓ Cloned successfully"
              else
                log "  ✗ Failed to clone"
                FAILED=$((FAILED + 1))
                continue
              fi
            else
              log "  Updating local copy..."
              (cd "$REPO_DIR" && ${pkgs.git}/bin/git fetch --all --prune >> "$LOG_FILE" 2>&1) || true
            fi

            # Check if Tangled remote exists
            cd "$REPO_DIR"
            TANGLED_REMOTE=$(${pkgs.git}/bin/git remote get-url tangled 2>/dev/null || echo "")
            TANGLED_URL="git@$TANGLED_KNOT:$TANGLED_REPO_PATH/$repo_name"

            if [ -z "$TANGLED_REMOTE" ]; then
              log "  Adding Tangled remote..."
              ${pkgs.git}/bin/git remote add tangled "$TANGLED_URL" || true
            elif [ "$TANGLED_REMOTE" != "$TANGLED_URL" ]; then
              log "  Updating Tangled remote URL..."
              ${pkgs.git}/bin/git remote set-url tangled "$TANGLED_URL"
            fi

            # Push to Tangled (mirror all branches and tags)
            log "  Pushing to Tangled..."
            if ${pkgs.git}/bin/git push tangled --all --force >> "$LOG_FILE" 2>&1 && \
               ${pkgs.git}/bin/git push tangled --tags --force >> "$LOG_FILE" 2>&1; then
              log "  ✓ Synced successfully"
              SYNCED=$((SYNCED + 1))
            else
              log "  ✗ Failed to push (repo may not exist on Tangled yet)"
              FAILED=$((FAILED + 1))
            fi

          done <<< "$REPOS"

          log "Sync complete: $SYNCED synced, $FAILED failed"
        '';
        StateDirectory = "github-tangled-sync";
      };
    };

    systemd.timers.github-tangled-sync = {
      description = "Timer for GitHub to Tangled sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
      };
    };
  };
}
