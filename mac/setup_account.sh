#!/usr/bin/env bash
set -e

# Ensure GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
  echo "📦 Installing gh …"; brew install gh; fi

# Authenticate if needed
if ! gh auth status >/dev/null 2>&1; then
  echo "🔐 Running 'gh auth login' …"; gh auth login; fi

GH_USER=$(gh api user --jq .login)

# === Fork required repositories ===
REPOS_TO_FORK=(
  "grll/claude-code-action"
  "grll/claude-code-base-action"
)

for SOURCE in "${REPOS_TO_FORK[@]}"; do
  DEST="$GH_USER/$(basename "$SOURCE")"
  if gh repo view "$DEST" >/dev/null 2>&1; then
    echo "✔️  Fork exists: $DEST"
  else
    echo "🔁 Forking $SOURCE -> $DEST …"
    gh repo fork "$SOURCE" --clone=false --default || { echo "❌ Fork failed for $SOURCE" >&2; exit 1; }
  fi
done

echo "🏷️  Action reference will be $GH_USER/claude-code-action@main"

# === Ensure Claude GitHub App is installed ===
APP_SLUG="claude"
INSTALL_URL="https://github.com/apps/${APP_SLUG}"

if ! gh api "user/installations" --paginate --jq '.installations[].app_slug' | grep -q "^${APP_SLUG}$"; then
  echo "⚙️  Opening browser to install Claude GitHub App …"
  if command -v open >/dev/null 2>&1; then
    open "$INSTALL_URL"
  else
    echo "👉 Please visit $INSTALL_URL and install the app to your account/org."
  fi
  echo "🔄 Press Enter after completing the installation …"; read -r
fi

echo "✅ setup_account complete!"