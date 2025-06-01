# Claude PR Assistant — Ubuntu Scripts

This folder contains Ubuntu‑native bash scripts that leverage **APT** package management and file-based credential storage.

| Script | Purpose | Run frequency |
|--------|---------|---------------|
| `setup_account.sh` | • Authenticates `gh`  •  Forks Claude action repos  •  Opens browser to install the Claude GitHub App | **Once** per GitHub account |
| `setup_repository.sh <owner/repo>` | Uploads secrets, adds the workflow, pushes PR | Per target repo |
| `update_token.sh  <owner/repo>` | Refreshes secrets when tokens rotate | Whenever needed / cron |

## Prerequisites
- **Ubuntu/Debian-based system** with `apt` package manager
- `gh`, `jq`, and `git` will auto‑install if missing
- Credentials file at **`$HOME/.config/claude-code/credentials.json`** with JSON:
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

## Setup
```bash
# Create the config directory if it doesn't exist
mkdir -p ~/.config/claude-code

# Create the credentials file with your Claude Code tokens
# You can obtain these from your Claude Code session
nano ~/.config/claude-code/credentials.json

# Make scripts executable
chmod +x *.sh
```

## Usage
```bash
# account setup
./setup_account.sh

# repo setup
./setup_repository.sh myuser/myrepo

# token refresh (example cron entry – runs daily at 02:15)
15 2 * * *  $HOME/claude_code_actions_setting_tool/scripts/ubuntu/update_token.sh myuser/myrepo
```

### Key Differences from macOS Version
- Uses **file-based storage** (`~/.config/claude-code/credentials.json`) instead of macOS Keychain
- Uses **APT** package manager instead of Homebrew
- Uses **xdg-open** or **gnome-open** to open browsers instead of macOS's `open` command
- No macOS-specific `security` command for credential management

### Security Notes
- Ensure the credentials file has proper permissions: `chmod 600 ~/.config/claude-code/credentials.json`
- The credentials file contains sensitive tokens - do not share or commit it to version control
- Consider using encrypted file systems or additional security measures for production environments

### Uninstall / Cleanup
Remove the workflow file (`.github/workflows/claude.yml`) and delete the three GitHub Secrets.

---