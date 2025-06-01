#!/usr/bin/env bash
set -euo pipefail

if [ -z "${1:-}" ]; then
  echo "❗Usage: $0 <github-owner/repo>" >&2
  exit 1
fi

GITHUB_REPO="$1"
KEYCHAIN_SERVICE_NAME="Claude Code-credentials"
TOKEN_FILE="$HOME/.claude_credentials.json"

# Get tokens
if command -v security >/dev/null 2>&1; then
  raw_json="$(security find-generic-password -s "$KEYCHAIN_SERVICE_NAME" -w 2>/dev/null || true)"
else
  raw_json="$(cat "$TOKEN_FILE" 2>/dev/null || true)"
fi
if [ -z "$raw_json" ]; then
  echo "❌ Credential data not found." >&2
  exit 1
fi

access_token="$(echo "$raw_json" | jq -r '.claudeAiOauth.accessToken')"
refresh_token="$(echo "$raw_json" | jq -r '.claudeAiOauth.refreshToken')"
expires_at="$(echo "$raw_json" | jq -r '.claudeAiOauth.expiresAt')"

# Update secrets
echo "🔄 Updating secrets on $GITHUB_REPO …"

gh secret set CLAUDE_ACCESS_TOKEN  --body "$access_token"  --repo "$GITHUB_REPO"
gh secret set CLAUDE_REFRESH_TOKEN --body "$refresh_token" --repo "$GITHUB_REPO"
gh secret set CLAUDE_EXPIRES_AT    --body "$expires_at"    --repo "$GITHUB_REPO"

echo "✅ Secrets updated successfully."
