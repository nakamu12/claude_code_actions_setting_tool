#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "Usage: $0 <owner/repo>" >&2; exit 1; fi

TARGET_REPO="$1"
KEYCHAIN_SERVICE_NAME="Claude Code-credentials"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
WORKFLOW_PATH=".github/workflows/claude.yml"

# Ensure cmds
for c in jq gh security git; do command -v $c >/dev/null || { echo "📦 installing $c"; brew install $c; }; done

# Auth
if ! gh auth status >/dev/null 2>&1; then gh auth login; fi
GH_USER=$(gh api user --jq .login)
ACTION_REF="$GH_USER/claude-code-action@main"

# Extract tokens
RAW=$(security find-generic-password -s "$KEYCHAIN_SERVICE_NAME" -w 2>/dev/null || true)
[ -z "$RAW" ] && { echo "Keychain missing" >&2; exit 1; }
ACC=$(echo "$RAW"|jq -r '.claudeAiOauth.accessToken')
REF=$(echo "$RAW"|jq -r '.claudeAiOauth.refreshToken')
EXP=$(echo "$RAW"|jq -r '.claudeAiOauth.expiresAt')

echo "Uploading secrets …";
gh secret set CLAUDE_ACCESS_TOKEN --body "$ACC" --repo "$TARGET_REPO"
gh secret set CLAUDE_REFRESH_TOKEN --body "$REF" --repo "$TARGET_REPO"
gh secret set CLAUDE_EXPIRES_AT  --body "$EXP" --repo "$TARGET_REPO"

gh repo clone "$TARGET_REPO" "$TMP_DIR/repo"; cd "$TMP_DIR/repo"
mkdir -p "$(dirname "$WORKFLOW_PATH")"
cp "$SCRIPT_DIR/workflows/claude.yml" "$WORKFLOW_PATH"
sed -i '' "s#OWNER_PLACEHOLDER/claude-code-action@main#$ACTION_REF#" "$WORKFLOW_PATH"

BRANCH="setup-claude-pr-action";
git checkout -b "$BRANCH"; git add "$WORKFLOW_PATH"; git commit -m "Add Claude PR Assistant";
git push -u origin "$BRANCH";

gh pr create --title "Add Claude PR Assistant" --body "Adds workflow using $ACTION_REF." --repo "$TARGET_REPO" --base main || true