# claude_code_actions_setting_tool – repository files (cross‑platform)

```
.
├── linux/
│   └── (TBD)
├── mac/
│   ├── README.md
│   ├── setup_account.sh
│   ├── setup_repository.sh
│   ├── update_tokens.sh
│   └── workflows/
│       └── claude.yml
└── windows/
    └── (TBD)
```

> **Note:** Linux & Windows script variants will follow the same interface as the `mac` version. Until they are added, you can run the mac scripts in a compatible shell (e.g., WSL, Git Bash) by providing a `~/.claude_credentials.json` token file.

---
## Root README (`README.md`)
```markdown
# Claude Code Actions Setting Tool

Automates installation of the **Claude PR Assistant** GitHub Action across repositories. Provides OS‑specific scripts under the `mac/`, `linux/`, and `windows/` directories.

## Features
- 🛠 Forks required Claude Actions repositories into **your** account
- 🔑 Installs the Claude GitHub App (browser flow)
- 🔐 Uploads `CLAUDE_*` OAuth secrets to any repo
- 🚀 Creates/updates the workflow file via pull‑request
- 🖥️ macOS Keychain support & `.claude_credentials.json` fallback for Linux/Windows

## Directory Layout
| Path | Purpose |
|------|---------|
| `mac/` | macOS‑optimized scripts & workflow template |
| `linux/` | Linux (bash) variant — *coming soon* |
| `windows/` | Windows (PowerShell) variant — *coming soon* |

## Quick Start (macOS example)
```bash
cd mac
# 1 – once per GitHub account
./setup_account.sh
# 2 – enable assistant in a repo
./setup_repository.sh myuser/myrepo
# 3 – refresh tokens (cron/launchd)
./update_tokens.sh myuser/myrepo
```

For Linux/Windows, copy the mac scripts as a starting point and adapt the package‑manager lines (`brew` → `apt-get` / `choco`).
