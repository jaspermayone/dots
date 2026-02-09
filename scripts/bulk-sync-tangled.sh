#!/usr/bin/env bash
# Bulk sync all GitHub repos to Tangled (non-interactive)
# Use this when repos are already created on Tangled

set -euo pipefail

# Configuration
GITHUB_USERNAME="${GITHUB_USERNAME:-jaspermayone}"
TANGLED_HANDLE="${TANGLED_HANDLE:-jaspermayone.tngl.sh}"
TANGLED_REPO_PATH="${TANGLED_REPO_PATH:-jaspermayone.com}"
TANGLED_KNOT="${TANGLED_KNOT:-knot.jaspermayone.com}"
WORK_DIR="${WORK_DIR:-/tmp/github-tangled-sync}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${BLUE}==>${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "======================================"
echo "  GitHub → Tangled Bulk Sync"
echo "======================================"
echo ""

# Create work directory
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

log "Fetching public GitHub repositories..."
REPOS=$(gh repo list "$GITHUB_USERNAME" \
  --source \
  --no-archived \
  --visibility public \
  --limit 1000 \
  --json name,url,defaultBranchRef \
  --jq '.[] | "\(.name)|\(.url)|\(.defaultBranchRef.name // "main")"')

TOTAL=$(echo "$REPOS" | wc -l | tr -d ' ')
log "Found $TOTAL repositories to sync"
echo ""

SYNCED=0
FAILED=0
COUNT=0

while IFS='|' read -r repo_name repo_url default_branch; do
  COUNT=$((COUNT + 1))
  echo "[$COUNT/$TOTAL] $repo_name"

  REPO_DIR="$WORK_DIR/$repo_name"

  # Clone or update
  if [ ! -d "$REPO_DIR" ]; then
    if git clone "$repo_url" "$REPO_DIR" >/dev/null 2>&1; then
      echo "  Cloned from GitHub"
    else
      error "  Failed to clone"
      FAILED=$((FAILED + 1))
      continue
    fi
  else
    echo "  Updating from GitHub..."
    (cd "$REPO_DIR" && git fetch --all --prune >/dev/null 2>&1) || true
  fi

  cd "$REPO_DIR"

  # Add/update Tangled remote
  TANGLED_URL="git@$TANGLED_KNOT:$TANGLED_REPO_PATH/$repo_name"
  CURRENT_TANGLED=$(git remote get-url tangled 2>/dev/null || echo "")

  if [ -z "$CURRENT_TANGLED" ]; then
    git remote add tangled "$TANGLED_URL" 2>/dev/null || true
  elif [ "$CURRENT_TANGLED" != "$TANGLED_URL" ]; then
    git remote set-url tangled "$TANGLED_URL"
  fi

  # Push to Tangled
  if git push tangled --all 2>&1 | grep -qE "Everything up-to-date|Writing objects|Total|^To "; then
    if git push tangled --tags 2>&1 | grep -qE "Everything up-to-date|Writing objects|Total|^To "; then
      success "  Synced"
      SYNCED=$((SYNCED + 1))
    else
      error "  Failed to push tags"
      FAILED=$((FAILED + 1))
    fi
  else
    error "  Failed to push"
    FAILED=$((FAILED + 1))
  fi

  cd "$WORK_DIR"
  echo ""
done <<< "$REPOS"

echo "======================================"
success "Sync complete!"
echo "  Synced: $SYNCED"
echo "  Failed: $FAILED"
echo "======================================"
echo ""

if [ $FAILED -gt 0 ]; then
  echo "Some repos failed. Common reasons:"
  echo "  - Repo not created on Tangled yet"
  echo "  - SSH key not configured"
  echo "  - Wrong knot server"
fi
