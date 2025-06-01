#!/usr/bin/env bash
set -euo pipefail

# Usage: setup_repository.sh <owner/repo>
[ -z "${1:-}" ] && { echo "Usage: $0 <owner/repo>" >&2; exit 1; }
TARGET_REPO="$1"

CREDENTIALS_FILE="$HOME/.config/claude-code/credentials.json"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
WORKFLOW_PATH=".github/workflows/claude.yml"
BRANCH_BASE="setup-claude-pr-action"

# Ensure required commands
for c in jq gh git; do
  if ! command -v "$c" >/dev/null; then
    echo "📦 Installing $c"
    case "$c" in
      jq) sudo apt-get update && sudo apt-get install -y jq ;;
      gh) # Install gh from official APT repository
        (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
          && sudo mkdir -p -m 755 /etc/apt/keyrings \
          && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
          && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
          && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
          && sudo apt update \
          && sudo apt install gh -y ;;
      git) sudo apt-get update && sudo apt-get install -y git ;;
    esac
  fi
done

# gh login if needed
if ! gh auth status >/dev/null 2>&1; then gh auth login; fi
GH_USER=$(gh api user --jq .login)
ACTION_REF="$GH_USER/claude-code-action@main"

# Extract tokens from credentials file
if [ ! -f "$CREDENTIALS_FILE" ]; then
  echo "❌ Credentials file not found at $CREDENTIALS_FILE" >&2
  echo "Please ensure Claude Code credentials are stored in the file with JSON format:" >&2
  echo '{
  "claudeAiOauth": {
    "accessToken": "...",
    "refreshToken": "...",
    "expiresAt": 1748721864056,
    "scopes": ["user:inference","user:profile"]
  }
}' >&2
  exit 1
fi

RAW=$(cat "$CREDENTIALS_FILE")
ACC=$(echo "$RAW" | jq -r '.claudeAiOauth.accessToken')
REF=$(echo "$RAW" | jq -r '.claudeAiOauth.refreshToken')
EXP=$(echo "$RAW" | jq -r '.claudeAiOauth.expiresAt')

echo "🔐 Uploading secrets …"
gh secret set CLAUDE_ACCESS_TOKEN --body "$ACC" --repo "$TARGET_REPO"
gh secret set CLAUDE_REFRESH_TOKEN --body "$REF" --repo "$TARGET_REPO"
gh secret set CLAUDE_EXPIRES_AT  --body "$EXP" --repo "$TARGET_REPO"

# Clone repo
GH_CLONE_DIR="$TMP_DIR/repo"
gh repo clone "$TARGET_REPO" "$GH_CLONE_DIR"
cd "$GH_CLONE_DIR"

# Prepare workflow (template now lives in project‑level workflows/)
mkdir -p "$(dirname "$WORKFLOW_PATH")"
cp "$ROOT_DIR/templates/claude.yml" "$WORKFLOW_PATH"
sed -i "s#OWNER_PLACEHOLDER/claude-code-action@main#$ACTION_REF#" "$WORKFLOW_PATH"

# Branch handling
BRANCH="$BRANCH_BASE"
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  BRANCH="${BRANCH_BASE}-$(date +%Y%m%d%H%M%S)"
fi

git checkout -b "$BRANCH"
git add "$WORKFLOW_PATH"
if ! git diff --cached --quiet; then
  git commit -m "Add/Update Claude PR Assistant workflow"
  git push -u origin "$BRANCH"
  gh pr create --title "Add Claude PR Assistant" --body "Adds or updates workflow using $ACTION_REF." --repo "$TARGET_REPO" --base main || true
fi