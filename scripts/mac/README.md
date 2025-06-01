# Claude PR Assistant — macOS Scripts

This folder contains mac‑native bash scripts that leverage **Homebrew** and the macOS Keychain.

| Script | Purpose | Run frequency |
|--------|---------|---------------|
| `setup_account.sh` | • Authenticates `gh`  •  Forks Claude action repos  •  Opens browser to install the Claude GitHub App | **Once** per GitHub account |
| `setup_repository.sh <owner/repo>` | Uploads secrets, adds the workflow, pushes PR | Per target repo |
| `update_tokens.sh  <owner/repo>` | Refreshes secrets when tokens rotate | Whenever needed / cron |

## Prerequisites
- **Homebrew** : `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
- `gh` & `jq` will auto‑install if missing
- Keychain item **“Claude Code‑credentials”** with JSON:
  ```json
  {
    "claudeAiOauth": {
      "accessToken": "...",
      "refreshToken": "...",
      "expiresAt": 1748721864056,
      "scopes": ["user:inference","user:profile"]
    }
  }
  ```

## Usage
```bash
# account setup
./setup_account.sh

# repo setup
./setup_repository.sh myuser/myrepo

# token refresh (example cron entry – runs daily at 02:15)
15 2 * * *  $HOME/claude_code_actions_setting_tool/mac/update_tokens.sh myuser/myrepo
```

### Uninstall / Cleanup
Remove the workflow file (`.github/workflows/claude.yml`) and delete the three GitHub Secrets.

---
