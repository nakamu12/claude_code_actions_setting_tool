# claude_code_actions_setting_tool

CLI scripts to **install and maintain** the Claude PR Assistant GitHub Action across repositories.

## Scripts

| Script | Purpose |
|--------|---------|
| `setup_account.sh` | Authenticate `gh` and fork the template repo. Run **once** per GitHub account. |
| `setup_repository.sh <owner/repo>` | Upload Claude OAuth tokens as Secrets, copy `workflows/claude.yml`, and open a pull‑request. |
| `update_tokens.sh <owner/repo>` | Refresh the three Secrets (access, refresh, expiresAt) whenever your Keychain updates. Ideal for cron. |

## Prerequisites
- macOS with **Homebrew**
- `gh`, `jq`, `git`, and `security` (auto‑installed if missing)
- Keychain item named **"Claude Code-credentials"** containing JSON with `accessToken`, `refreshToken`, and `expiresAt`.

## Usage
```bash
# One‑time account setup
./setup_account.sh

# Enable Claude PR Assistant on a repo
./setup_repository.sh your-username/your-repo

# Periodic secret refresh (cron / launchd)
./update_tokens.sh your-username/your-repo
```

---
