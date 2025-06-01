# Windows Setup Scripts for Claude Code Actions

This directory contains PowerShell scripts to set up Claude PR Assistant on Windows.

## Prerequisites

- Windows 10/11 with PowerShell 5.1 or PowerShell Core 7+
- GitHub account
- Claude Code OAuth tokens (from signing in to Claude Code)
- Internet connection

## Scripts Overview

### 1. `setup_account.ps1`
Initial one-time setup for your GitHub account:
- Installs GitHub CLI (via winget, Chocolatey, or manual)
- Authenticates with GitHub
- Forks required action repositories
- Guides you to install Claude GitHub App

### 2. `setup_repository.ps1`
Configures a specific repository to use Claude:
- Retrieves OAuth tokens from Windows Credential Manager
- Adds tokens as GitHub secrets
- Creates a pull request to add Claude workflow

### 3. `update_token.ps1`
Updates OAuth tokens to prevent expiration:
- Retrieves latest tokens from Windows Credential Manager
- Updates repository secrets
- Can be scheduled to run automatically

## Setup Instructions

### Step 1: Account Setup (One-time)

Run in PowerShell:
```powershell
.\setup_account.ps1
```

This will:
1. Install GitHub CLI if not present
2. Authenticate you with GitHub
3. Fork the required repositories
4. Direct you to install the Claude app

### Step 2: Repository Setup

For each repository you want to enable:
```powershell
.\setup_repository.ps1 -Repository owner/repo
```

Example:
```powershell
.\setup_repository.ps1 -Repository myusername/myproject
```

### Step 3: Token Updates (Optional but Recommended)

Manually update tokens:
```powershell
.\update_token.ps1 -Repository owner/repo
```

## Automatic Token Updates

To set up automatic token updates using Windows Task Scheduler:

1. Open Task Scheduler (`taskschd.msc`)
2. Create a new task with these settings:
   - **General**: Run whether user is logged on or not
   - **Triggers**: Daily at a convenient time
   - **Actions**: 
     - Program: `powershell.exe`
     - Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\update_token.ps1" -Repository owner/repo`
   - **Conditions**: Start only if computer is on AC power (optional)

## Credential Storage

Claude OAuth tokens are stored in Windows Credential Manager under:
- **Name**: `Claude Code-credentials`
- **Type**: Generic Credential

To view stored credentials:
1. Open Credential Manager (`control /name Microsoft.CredentialManager`)
2. Go to "Windows Credentials"
3. Look for "Claude Code-credentials"

## Troubleshooting

### "Script cannot be loaded" Error
If you get an execution policy error, run:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### GitHub CLI Installation Issues
- **Option 1**: Install via [winget](https://github.com/microsoft/winget-cli)
- **Option 2**: Install via [Chocolatey](https://chocolatey.org/)
- **Option 3**: Download manually from [GitHub CLI releases](https://github.com/cli/cli/releases)

### Credentials Not Found
1. Ensure you've signed in to Claude Code
2. Check Credential Manager for "Claude Code-credentials"
3. Try signing out and back in to Claude Code

### Permission Errors
- For repository setup: Ensure you have admin/write access to the repository
- For account setup: Some operations may require running as Administrator

## Security Notes

- OAuth tokens are stored securely in Windows Credential Manager
- Tokens are only accessible to your Windows user account
- Repository secrets are encrypted by GitHub
- Never share or commit tokens directly

## Help

For help with any script, use the `-Help` flag:
```powershell
.\setup_account.ps1 -Help
.\setup_repository.ps1 -Help
.\update_token.ps1 -Help
```