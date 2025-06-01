# Claude PR Assistant — Windows Scripts

This folder contains Windows PowerShell scripts for setting up Claude Code Actions on Windows systems.

| Script | Purpose | Run frequency |
|--------|---------|---------------|
| `setup_account.ps1` | • Authenticates `gh` • Forks Claude action repos • Opens browser to install the Claude GitHub App | **Once** per GitHub account |
| `setup_repository.ps1 <owner/repo>` | Uploads secrets, adds the workflow, pushes PR | Per target repo |
| `update_token.ps1 <owner/repo>` | Refreshes secrets when tokens rotate | Whenever needed / scheduled task |

## Prerequisites

1. **PowerShell** 5.1 or later (comes with Windows 10/11)
2. **GitHub CLI** (`gh`) - will auto-install via winget or Chocolatey if available
3. **Git** - must be installed manually from [git-scm.com](https://git-scm.com)
4. **Claude Code credentials** stored in Windows Credential Manager with:
   - Target name: `Claude Code-credentials`
   - Password containing JSON:
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

## Installation Methods

### GitHub CLI Installation Options:
- **winget** (Windows 11/10): `winget install --id GitHub.cli`
- **Chocolatey**: `choco install gh`
- **Manual**: Download from [cli.github.com](https://cli.github.com)

## Usage

### 1. Initial Account Setup
```powershell
# Run from the windows directory
.\setup_account.ps1
```

### 2. Repository Setup
```powershell
# Setup a specific repository
.\setup_repository.ps1 myuser/myrepo
```

### 3. Token Updates
```powershell
# Update tokens for a repository
.\update_token.ps1 myuser/myrepo
```

## Scheduled Token Updates

To automatically update tokens, create a Windows Task Scheduler task:

1. Open Task Scheduler (`taskschd.msc`)
2. Create Basic Task → Name it "Claude Token Update"
3. Trigger: Daily (or your preferred schedule)
4. Action: Start a program
   - Program: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\update_token.ps1" owner/repo`
5. Finish and test the task

### Alternative: Using Task Scheduler via PowerShell
```powershell
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument '-ExecutionPolicy Bypass -File "C:\path\to\claude_code_actions_setting_tool\scripts\windows\update_token.ps1" owner/repo'
$trigger = New-ScheduledTaskTrigger -Daily -At 2:15AM
Register-ScheduledTask -TaskName "Claude Token Update" -Action $action -Trigger $trigger
```

## Execution Policy

If you encounter execution policy errors, run PowerShell as Administrator and execute:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Or run scripts with:
```powershell
powershell -ExecutionPolicy Bypass -File .\script.ps1
```

## Storing Credentials in Windows Credential Manager

To store Claude credentials:

1. Open Credential Manager: `control /name Microsoft.CredentialManager`
2. Click "Windows Credentials" → "Add a generic credential"
3. Enter:
   - Internet or network address: `Claude Code-credentials`
   - User name: `claude` (or any value)
   - Password: The JSON string with your OAuth tokens

### Via PowerShell:
```powershell
$json = @'
{
  "claudeAiOauth": {
    "accessToken": "your-access-token",
    "refreshToken": "your-refresh-token",
    "expiresAt": 1748721864056,
    "scopes": ["user:inference","user:profile"]
  }
}
'@

cmdkey /generic:"Claude Code-credentials" /user:"claude" /pass:$json
```

## Troubleshooting

### Common Issues:

1. **"Script cannot be loaded"** - Execution policy issue
   - Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`

2. **"gh is not recognized"** - GitHub CLI not in PATH
   - Restart PowerShell after installation
   - Or add to PATH manually: `$env:Path += ";C:\Program Files\GitHub CLI"`

3. **"Credential not found"** - Windows Credential Manager issue
   - Verify credential exists with correct target name
   - Check JSON format is valid

4. **"Failed to parse credentials JSON"** - Invalid JSON in credential
   - Ensure proper JSON formatting
   - Check for escaped quotes if entered via GUI

### Uninstall / Cleanup

1. Remove workflow file from repository: `.github/workflows/claude.yml`
2. Delete GitHub Secrets: `CLAUDE_ACCESS_TOKEN`, `CLAUDE_REFRESH_TOKEN`, `CLAUDE_EXPIRES_AT`
3. Remove Windows Credential Manager entry: `cmdkey /delete:"Claude Code-credentials"`
4. Delete any scheduled tasks for token updates

---