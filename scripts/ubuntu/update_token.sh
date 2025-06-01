#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "❗Usage: $0 <github-owner/repo>" >&2
  exit 1
fi

GITHUB_REPO="$1"
CREDENTIALS_FILE="$HOME/.config/claude-code/credentials.json"

# Get tokens from credentials file
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

raw_json=$(cat "$CREDENTIALS_FILE")
access_token="$(echo "$raw_json" | jq -r '.claudeAiOauth.accessToken')"
refresh_token="$(echo "$raw_json" | jq -r '.claudeAiOauth.refreshToken')"
expires_at="$(echo "$raw_json" | jq -r '.claudeAiOauth.expiresAt')"

# Update secrets
echo "🔄 Updating secrets on $GITHUB_REPO …"

gh secret set CLAUDE_ACCESS_TOKEN  --body "$access_token"  --repo "$GITHUB_REPO"
gh secret set CLAUDE_REFRESH_TOKEN --body "$refresh_token" --repo "$GITHUB_REPO"
gh secret set CLAUDE_EXPIRES_AT    --body "$expires_at"    --repo "$GITHUB_REPO"

echo "✅ Secrets updated successfully."