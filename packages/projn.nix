{ pkgs, lib, ... }:

pkgs.writeShellApplication {
  name = "projn";

  runtimeInputs = with pkgs; [
    gh
    git
    jq
    curl
  ];

  text = ''
    set -euo pipefail

    # Configuration - these can be overridden by environment variables
    GITHUB_USERNAME="''${GITHUB_USERNAME:-jaspermayone}"
    TANGLED_HANDLE="''${TANGLED_HANDLE:-jaspermayone.tngl.sh}"
    TANGLED_KNOT="''${TANGLED_KNOT:-knot.jaspermayone.com}"
    TANGLED_PDS="''${TANGLED_PDS:-https://tangled.sh}"
    PROJECTS_DIR="''${PROJECTS_DIR:-$HOME/projects}"

    # Colors
    GREEN='\033[0;32m'
    BLUE='\033[0;34m'
    RED='\033[0;31m'
    NC='\033[0m' # No Color

    log() {
      echo -e "''${BLUE}===>''${NC} $1"
    }

    success() {
      echo -e "''${GREEN}✓''${NC} $1"
    }

    error() {
      echo -e "''${RED}✗''${NC} $1"
      exit 1
    }

    # Usage
    if [ $# -lt 1 ]; then
      echo "Usage: projn <project-name> [description]"
      echo ""
      echo "Creates a new project on both GitHub and Tangled with a local directory."
      echo ""
      echo "Environment variables:"
      echo "  GITHUB_USERNAME  - GitHub username (default: jaspermayone)"
      echo "  TANGLED_HANDLE   - Tangled handle (default: jaspermayone.tngl.sh)"
      echo "  TANGLED_KNOT     - Tangled knot server (default: knot.jaspermayone.com)"
      echo "  TANGLED_PDS      - Tangled PDS URL (default: https://tangled.sh)"
      echo "  TANGLED_TOKEN    - Tangled authentication token (required for API)"
      echo "  PROJECTS_DIR     - Base directory for projects (default: ~/projects)"
      exit 1
    fi

    PROJECT_NAME="$1"
    DESCRIPTION="''${2:-A new project}"

    # Validate project name
    if [[ ! "$PROJECT_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
      error "Project name must contain only letters, numbers, hyphens, and underscores"
    fi

    log "Creating project: $PROJECT_NAME"
    echo "    Description: $DESCRIPTION"
    echo ""

    # Create local directory
    PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"
    if [ -d "$PROJECT_DIR" ]; then
      error "Directory $PROJECT_DIR already exists"
    fi

    mkdir -p "$PROJECT_DIR"
    cd "$PROJECT_DIR"

    log "Initializing git repository..."
    git init -b main

    # Create README
    cat > README.md <<EOF
# $PROJECT_NAME

$DESCRIPTION

## Created with projn

This project is hosted on:
- GitHub: https://github.com/$GITHUB_USERNAME/$PROJECT_NAME
- Tangled: https://tangled.org/$TANGLED_HANDLE/$PROJECT_NAME
EOF

    git add README.md
    git commit -m "Initial commit"

    # Create GitHub repository
    log "Creating GitHub repository..."
    if gh repo create "$GITHUB_USERNAME/$PROJECT_NAME" \
      --public \
      --description "$DESCRIPTION" \
      --source=. \
      --remote=origin \
      --push; then
      success "GitHub repository created"
    else
      error "Failed to create GitHub repository"
    fi

    # Create Tangled repository via XRPC
    log "Creating Tangled repository..."

    # First, create the repo record
    REPO_RKEY=$(date +%s%N | cut -c1-13) # TID-like timestamp
    GITHUB_URL="https://github.com/$GITHUB_USERNAME/$PROJECT_NAME"

    # Create repo via XRPC API
    # Note: This requires TANGLED_TOKEN to be set
    if [ -z "''${TANGLED_TOKEN:-}" ]; then
      echo ""
      echo "⚠️  TANGLED_TOKEN not set. To auto-create on Tangled, you need to:"
      echo "   1. Get your auth token from Tangled"
      echo "   2. Export it: export TANGLED_TOKEN='your-token'"
      echo ""
      echo "For now, manually create the repo on Tangled:"
      echo "   1. Visit: https://tangled.org"
      echo "   2. Click '+' → 'repository'"
      echo "   3. Name: $PROJECT_NAME"
      echo "   4. Knot: $TANGLED_KNOT"
      echo ""
      read -p "Press Enter once you've created the repo on Tangled..."
    else
      # TODO: Implement XRPC API call to create repo
      # This requires implementing the full XRPC auth flow
      log "XRPC API integration not yet implemented"
      echo "Please manually create the repo on Tangled for now."
      read -p "Press Enter once you've created the repo on Tangled..."
    fi

    # Add Tangled remote
    log "Adding Tangled remote..."
    TANGLED_URL="ssh://git@$TANGLED_KNOT:$TANGLED_HANDLE/$PROJECT_NAME"
    git remote add tangled "$TANGLED_URL"

    # Push to Tangled
    log "Pushing to Tangled..."
    if git push tangled main; then
      success "Pushed to Tangled"
    else
      error "Failed to push to Tangled (make sure the repo was created)"
    fi

    success "Project created successfully!"
    echo ""
    echo "Local directory: $PROJECT_DIR"
    echo "GitHub: https://github.com/$GITHUB_USERNAME/$PROJECT_NAME"
    echo "Tangled: https://tangled.org/$TANGLED_HANDLE/$PROJECT_NAME"
    echo ""
    echo "To push to both remotes:"
    echo "  git push origin main    # Push to GitHub"
    echo "  git push tangled main   # Push to Tangled"
    echo "  git push --all origin tangled  # Push all branches to both"
  '';
}
