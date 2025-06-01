# Claude Code Actions Setting Tool

Cross‑platform shell scripts to set up and maintain the **Claude PR Assistant** GitHub Action.

---
## Supported OS
| OS | Package manager assumed | Notes |
|----|-------------------------|-------|
| **macOS** | Homebrew (`brew`) | Uses Keychain for token storage |
| **Linux** | `apt` (Debian/Ubuntu) fallback | If `security` is unavailable, reads `~/.claude_credentials.json` |
| **Windows** | Chocolatey (`choco`) | Use Git Bash / PowerShell; token file fallback |

> **Token storage on Linux/Windows**  
> Save the JSON you see in Keychain on macOS to `~/.claude_credentials.json`.

---
## Scripts
| Script | macOS | Linux | Windows |
|--------|-------|-------|---------|
| `setup_account.sh` | ✅ | ✅* | ✅* |
| `setup_repository.sh <owner/repo>` | ✅ | ✅ | ✅ |
| `update_tokens.sh <owner/repo>` | ✅ | ✅ | ✅ |

\*Fork & App install open the default browser (`open`, `xdg-open`, or `start`).

---
## Quick Start
```bash
# 1. Account‑level prerequisites (once)
./setup_account.sh

# 2. Enable Claude PR Assistant on a repo
./setup_repository.sh myuser/myrepo

# 3. Refresh tokens periodically (cron / Task Scheduler)
./update_tokens.sh myuser/myrepo
```

---
### FAQ
- **Q: How do I install dependencies manually?**  
  • macOS: `brew install gh jq`  
  • Debian: `sudo apt-get install gh jq`  
  • Windows (Admin): `choco install gh jq`

- **Q: Where do I get tokens on Linux/Windows?**  
  Obtain them once on macOS, or via browser dev tools, then place the JSON as `~/.claude_credentials.json`.

---
