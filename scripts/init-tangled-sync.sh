#!/usr/bin/env bash
# Initial setup script for GitHub → Tangled sync
# This script helps you create Tangled repos for all your existing public GitHub repos

set -euo pipefail

# Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-jaspermayone}"
TANGLED_HANDLE="${TANGLED_HANDLE:-jaspermayone.tngl.sh}"
TANGLED_KNOT="${TANGLED_KNOT:-knot.jaspermayone.com}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log() {
  echo -e "${BLUE}==>${NC} $1"
}

info() {
  echo -e "${YELLOW}ℹ${NC}  $1"
}

success() {
  echo -e "${GREEN}✓${NC} $1"
}

error() {
  echo -e "${RED}✗${NC} $1"
}

echo ""
echo "======================================"
echo "  GitHub → Tangled Initial Sync"
echo "======================================"
echo ""
echo "This script will help you create Tangled repos for all your public GitHub repos."
echo ""
echo "Configuration:"
echo "  GitHub: $GITHUB_USERNAME"
echo "  Tangled: $TANGLED_HANDLE"
echo "  Knot: $TANGLED_KNOT"
echo ""

# Get list of public repos
log "Fetching public GitHub repositories..."
REPOS=$(gh repo list "$GITHUB_USERNAME" \
  --source \
  --no-archived \
  --visibility public \
  --limit 1000 \
  --json name,url,description,defaultBranchRef \
  --jq '.[] | "\(.name)|\(.url)|\(.description // "")|\(.defaultBranchRef.name // "main")"')

if [ -z "$REPOS" ]; then
  error "No public repositories found"
  exit 1
fi

REPO_COUNT=$(echo "$REPOS" | wc -l | tr -d ' ')
success "Found $REPO_COUNT public repositories"
echo ""

# Display repos
echo "Repositories to sync:"
echo "$REPOS" | while IFS='|' read -r name url desc branch; do
  echo "  • $name"
done
echo ""

info "For each repo, you'll need to manually create it on Tangled (for now)."
info "In the future, this will be automated via the XRPC API."
echo ""

read -p "Press Enter to start the process, or Ctrl+C to cancel..."
echo ""

# Process each repo
CREATED=0
SKIPPED=0

echo "$REPOS" | while IFS='|' read -r repo_name repo_url description default_branch; do
  echo ""
  log "Repository: $repo_name"
  echo "  Description: ${description:-No description}"
  echo "  GitHub URL: $repo_url"
  echo "  Default branch: $default_branch"
  echo ""

  info "Steps to create on Tangled:"
  echo "  1. Visit: https://tangled.org"
  echo "  2. Click the '+' icon → 'repository'"
  echo "  3. Fill in:"
  echo "     Name: $repo_name"
  echo "     Knot: $TANGLED_KNOT"
  echo "     Description: ${description:-No description}"
  echo "  4. Click 'Create'"
  echo ""

  read -p "Have you created this repo on Tangled? [y/N/s(kip)/q(uit)]: " answer

  case "$answer" in
    [Yy]* )
      echo "  Testing SSH connection..."
      TANGLED_URL="ssh://git@$TANGLED_KNOT:$TANGLED_HANDLE/$repo_name"

      # Clone to temp location and push
      TEMP_DIR=$(mktemp -d)
      if git clone "$repo_url" "$TEMP_DIR/$repo_name" >/dev/null 2>&1; then
        cd "$TEMP_DIR/$repo_name"
        git remote add tangled "$TANGLED_URL"

        if git push tangled --all 2>&1 | grep -q "Everything up-to-date\|Writing objects"; then
          success "Successfully synced $repo_name"
          CREATED=$((CREATED + 1))
        else
          error "Failed to push to Tangled"
        fi

        cd - >/dev/null
        rm -rf "$TEMP_DIR"
      else
        error "Failed to clone from GitHub"
      fi
      ;;
    [Ss]* )
      info "Skipped $repo_name"
      SKIPPED=$((SKIPPED + 1))
      ;;
    [Qq]* )
      echo ""
      info "Sync process interrupted"
      echo "Processed: $CREATED synced, $SKIPPED skipped"
      exit 0
      ;;
    * )
      info "Skipped $repo_name"
      SKIPPED=$((SKIPPED + 1))
      ;;
  esac
done

echo ""
echo "======================================"
success "Initial sync complete!"
echo "  Synced: $CREATED"
echo "  Skipped: $SKIPPED"
echo "======================================"
echo ""
info "Next steps:"
echo "  1. Enable the github-tangled-sync service for nightly syncs"
echo "  2. Use 'projn <name>' to create new projects on both platforms"
echo ""
