#!/usr/bin/env bash
set -euo pipefail

# Usage: setup_repository.sh <owner/repo>
[ -z "${1:-}" ] && { echo "Usage: $0 <owner/repo>" >&2; exit 1; }
TARGET_REPO="$1"

KEYCHAIN_SERVICE_NAME="Claude Code-credentials"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
WORKFLOW_PATH=".github/workflows/claude.yml"
BRANCH_BASE="setup-claude-pr-action"

# Ensure required commands
for c in jq gh security git; do command -v "$c" >/dev/null || { echo "📦 installing $c"; brew install "$c"; }; done

# gh login if needed
if ! gh auth status >/dev/null 2>&1; then gh auth login; fi
GH_USER=$(gh api user --jq .login)
ACTION_REF="$GH_USER/claude-code-action@main"

# Extract tokens from Keychain
RAW=$(security find-generic-password -s "$KEYCHAIN_SERVICE_NAME" -w 2>/dev/null || true)
[ -z "$RAW" ] && { echo "Keychain entry not found" >&2; exit 1; }
ACC=$(echo "$RAW" | jq -r '.claudeAiOauth.accessToken')
REF=$(echo "$RAW" | jq -r '.claudeAiOauth.refreshToken')
EXP=$(echo "$RAW" | jq -r '.claudeAiOauth.expiresAt')

# Upload secrets
for pair in CLAUDE_ACCESS_TOKEN "$ACC" CLAUDE_REFRESH_TOKEN "$REF" CLAUDE_EXPIRES_AT "$EXP"; do :; done

echo "🔐 Uploading secrets …"
gh secret set CLAUDE_ACCESS_TOKEN --body "$ACC" --repo "$TARGET_REPO"
gh secret set CLAUDE_REFRESH_TOKEN --body "$REF" --repo "$TARGET_REPO"
gh secret set CLAUDE_EXPIRES_AT  --body "$EXP" --repo "$TARGET_REPO"

# Clone repo
GH_CLONE_DIR="$TMP_DIR/repo"
gh repo clone "$TARGET_REPO" "$GH_CLONE_DIR"
cd "$GH_CLONE_DIR"

# Prepare workflow
mkdir -p "$(dirname "$WORKFLOW_PATH")"
cp "$SCRIPT_DIR/workflows/claude.yml" "$WORKFLOW_PATH"
sed -i '' "s#OWNER_PLACEHOLDER/claude-code-action@main#$ACTION_REF#" "$WORKFLOW_PATH"

# Determine branch name (avoid non‑fast‑forward issues)
BRANCH="$BRANCH_BASE"
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  TS=$(date +%Y%m%d%H%M%S)
  BRANCH="${BRANCH_BASE}-${TS}"
  echo "⚠️  Remote branch '$BRANCH_BASE' already exists. Using new branch '$BRANCH'"
fi

git checkout -b "$BRANCH"
git add "$WORKFLOW_PATH"
if git diff --cached --quiet; then
  echo "🛈 Workflow already up to date. Skipping commit & PR."
else
  git commit -m "Add/Update Claude PR Assistant workflow"
  if ! git push -u origin "$BRANCH"; then
    echo "❌ Push failed. Please resolve git issues manually." >&2
    exit 1
  fi

  gh pr create \
    --title "Add Claude PR Assistant" \
    --body  "Adds or updates workflow using $ACTION_REF." \
    --repo  "$TARGET_REPO" \
    --base  "main" || true
  echo "🎉 PR created on branch '$BRANCH'"
fi
