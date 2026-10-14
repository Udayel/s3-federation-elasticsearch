#!/bin/bash

###############################################################################
# Push Repository to GitHub
# Creates remote and pushes all commits
###############################################################################

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_header() {
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
}

print_step() {
  echo -e "${YELLOW}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

main() {
  print_header "Push Repository to GitHub"

  # Check parameters
  if [ $# -lt 1 ]; then
    print_error "Missing GitHub username"
    echo ""
    echo "Usage: bash scripts/push-to-github.sh <GITHUB_USERNAME> [REPO_NAME] [USE_SSH]"
    echo ""
    echo "Example:"
    echo "  bash scripts/push-to-github.sh Udayel"
    echo "  bash scripts/push-to-github.sh Udayel s3-federation-elasticsearch"
    echo "  bash scripts/push-to-github.sh Udayel s3-federation-elasticsearch ssh"
    echo ""
    exit 1
  fi

  GITHUB_USER=$1
  REPO_NAME=${2:-s3-federation-elasticsearch}
  USE_SSH=${3:-http}

  echo ""
  echo "Configuration:"
  echo "  GitHub User: $GITHUB_USER"
  echo "  Repository: $REPO_NAME"
  echo "  Protocol: $USE_SSH"
  echo ""

  # Determine URL
  if [ "$USE_SSH" = "ssh" ]; then
    REPO_URL="git@github.com:$GITHUB_USER/$REPO_NAME.git"
    print_step "Using SSH protocol"
  else
    REPO_URL="https://github.com/$GITHUB_USER/$REPO_NAME.git"
    print_step "Using HTTPS protocol"
  fi

  echo ""
  print_step "GitHub Repository URL:"
  echo "  $REPO_URL"
  echo ""

  # Check if remote already exists
  if git remote get-url origin > /dev/null 2>&1; then
    print_step "Updating existing remote..."
    git remote set-url origin "$REPO_URL"
  else
    print_step "Adding remote origin..."
    git remote add origin "$REPO_URL"
  fi

  # Rename branch to main if needed
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [ "$CURRENT_BRANCH" != "main" ]; then
    print_step "Renaming branch to main..."
    git branch -M main
  else
    print_step "Branch already named main"
  fi

  # Show commits before push
  echo ""
  echo "Commits to push:"
  git log --oneline
  echo ""

  # Push to GitHub
  print_step "Pushing to GitHub..."
  echo ""

  if git push -u origin main; then
    echo ""
    print_header "✅ Successfully Pushed to GitHub!"
    echo ""
    echo "Repository is now live at:"
    echo "  https://github.com/$GITHUB_USER/$REPO_NAME"
    echo ""
    echo "Next steps:"
    echo "  1. Visit GitHub repository"
    echo "  2. Add topics (elasticsearch, s3-federation, aws)"
    echo "  3. Update repository description if needed"
    echo "  4. Share repository URL"
    echo ""
  else
    print_error "Failed to push to GitHub"
    echo ""
    echo "Troubleshooting:"
    echo "  1. Verify repository exists on GitHub"
    echo "  2. Check GitHub credentials"
    echo "  3. If using SSH, verify keys are configured"
    echo "  4. Run: git remote -v (to check remote URL)"
    echo ""
    exit 1
  fi
}

main "$@"
