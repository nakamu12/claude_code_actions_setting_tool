#!/usr/bin/env bash
set -e

# Ensure GitHub CLI
if ! command -v gh >/dev/null 2>&1; then
  echo "📦 Installing gh …"
  # Install gh from official APT repository
  (type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
    && sudo mkdir -p -m 755 /etc/apt/keyrings \
    && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y
fi

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
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$INSTALL_URL"
  elif command -v gnome-open >/dev/null 2>&1; then
    gnome-open "$INSTALL_URL"
  else
    echo "👉 Please visit $INSTALL_URL and install the app to your account/org."
  fi
  echo "🔄 Press Enter after completing the installation …"; read -r
fi

echo "✅ setup_account complete!"