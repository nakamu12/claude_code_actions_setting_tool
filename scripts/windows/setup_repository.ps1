# Claude PR Assistant - Windows Repository Setup Script

# Simple argument handling - just use $args[0]
if ($args.Count -eq 0) {
    Write-Host "[ERROR] Repository argument is required. Usage: .\setup_repository.ps1 owner/repo" -ForegroundColor Red
    Write-Host "Example: .\setup_repository.ps1 nakamu12/codex_test" -ForegroundColor Yellow
    exit 1
}

$TargetRepo = $args[0].ToString().Trim()

Write-Host "[DEBUG] Received arguments: $($args.Count)" -ForegroundColor Gray
Write-Host "[DEBUG] Processing repository: '$TargetRepo'" -ForegroundColor Gray

# Validate repository format
if ($TargetRepo -notmatch "^[^/]+/[^/]+$") {
    Write-Host "[ERROR] Invalid repository format. Use: owner/repo" -ForegroundColor Red
    Write-Host "[ERROR] You provided: '$TargetRepo'" -ForegroundColor Red
    exit 1
}

Write-Host "[SETUP] Setting up Claude PR Assistant for $TargetRepo..." -ForegroundColor Green

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Constants
$CREDENTIAL_TARGET = "Claude Code-credentials"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT_DIR = Split-Path -Parent (Split-Path -Parent $SCRIPT_DIR)
$TMP_DIR = New-TemporaryFile | ForEach-Object { Remove-Item $_; New-Item -ItemType Directory -Path $_ }
$WORKFLOW_PATH = ".github/workflows/claude.yml"
$BRANCH_BASE = "setup-claude-pr-action"

# Ensure required commands
$requiredCommands = @{
    "gh" = "GitHub CLI (https://cli.github.com)"
    "git" = "Git (https://git-scm.com)"
}

foreach ($cmd in $requiredCommands.Keys) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] $cmd is not installed. Please install $($requiredCommands[$cmd])" -ForegroundColor Red
        exit 1
    }
}

# Authenticate with gh if needed
try {
    gh auth status | Out-Null
}
catch {
    Write-Host "[AUTH] Running 'gh auth login'..." -ForegroundColor Yellow
    gh auth login
}

$GH_USER = gh api user --jq .login
$ACTION_REF = "$GH_USER/claude-code-action@main"

function Get-ClaudeCredentialsFromWSL {
    try {
        Write-Host "[WSL] Attempting to access WSL environment..." -ForegroundColor Cyan
        
        # First, check if WSL is available
        try {
            $wslCheck = wsl --list --quiet
            Write-Host "[WSL] WSL is available" -ForegroundColor Green
        }
        catch {
            Write-Host "[WSL] WSL not available or not configured" -ForegroundColor Yellow
            return $null
        }
        
        # Get WSL username
        try {
            $wslUser = wsl whoami
            if ($wslUser) {
                $wslUser = $wslUser.Trim()
                Write-Host "[WSL] WSL username: $wslUser" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "[WSL] Could not get WSL username" -ForegroundColor Yellow
            $wslUser = "nakamurar39"  # fallback to known username
        }
        
        # Try to get credentials from WSL claude-code configuration with absolute paths
        $wslCredentialPaths = @(
            "/home/$wslUser/.claude/.credentials.json",
            "/home/$wslUser/.config/claude/credentials.json", 
            "/home/$wslUser/.claude/credentials.json",
            "/home/$wslUser/.config/anthropic/credentials.json"
        )
        
        # Also try with tilde expansion
        $wslCredentialPaths += @(
            "~/.claude/.credentials.json",
            "~/.config/claude/credentials.json",
            "~/.claude/credentials.json",
            "~/.config/anthropic/credentials.json"
        )
        
        foreach ($credPath in $wslCredentialPaths) {
            Write-Host "[WSL] Checking: $credPath" -ForegroundColor Gray
            
            try {
                # Check if file exists first
                $testResult = wsl test -f "$credPath"
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[WSL] File exists: $credPath" -ForegroundColor Green
                    
                    # Try to read the file
                    $credentialJson = wsl cat "$credPath"
                    if ($LASTEXITCODE -eq 0 -and $credentialJson -and $credentialJson.Trim() -ne "") {
                        Write-Host "[WSL] Successfully read credentials from: $credPath" -ForegroundColor Green
                        # Join multi-line output if needed
                        if ($credentialJson -is [array]) {
                            $credentialJson = $credentialJson -join ""
                        }
                        return $credentialJson
                    } else {
                        Write-Host "[WSL] Failed to read file content: $credPath" -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "[WSL] File not found: $credPath" -ForegroundColor Gray
                }
            }
            catch {
                Write-Host "[WSL] Error accessing $credPath : $_" -ForegroundColor Yellow
            }
        }
        
        # Try Windows filesystem access to WSL as fallback
        Write-Host "[WSL] Trying Windows filesystem access to WSL..." -ForegroundColor Cyan
        $windowsWslPaths = @(
            "\\wsl$\Ubuntu\home\$wslUser\.claude\.credentials.json",
            "\\wsl$\Ubuntu-20.04\home\$wslUser\.claude\.credentials.json",
            "\\wsl$\Ubuntu-22.04\home\$wslUser\.claude\.credentials.json"
        )
        
        foreach ($winPath in $windowsWslPaths) {
            Write-Host "[WSL] Checking Windows path: $winPath" -ForegroundColor Gray
            try {
                if (Test-Path $winPath) {
                    Write-Host "[WSL] Found via Windows path: $winPath" -ForegroundColor Green
                    $credentialJson = Get-Content $winPath -Raw
                    if ($credentialJson -and $credentialJson.Trim() -ne "") {
                        Write-Host "[WSL] Successfully read via Windows filesystem" -ForegroundColor Green
                        return $credentialJson
                    }
                }
            }
            catch {
                Write-Host "[WSL] Error accessing via Windows path: $_" -ForegroundColor Yellow
            }
        }
        
        return $null
    }
    catch {
        Write-Host "[WSL] Error accessing WSL credentials: $_" -ForegroundColor Yellow
        return $null
    }
}

# Function to get credentials from Windows Credential Manager
function Get-ClaudeCredentials {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;

    public class CredentialManager {
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool CredFree([In] IntPtr cred);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct CREDENTIAL {
            public int Flags;
            public int Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public int CredentialBlobSize;
            public IntPtr CredentialBlob;
            public int Persist;
            public int AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        public static string GetCredential(string target) {
            IntPtr credPtr;
            if (!CredRead(target, 1, 0, out credPtr)) {
                return null;
            }

            try {
                CREDENTIAL cred = Marshal.PtrToStructure<CREDENTIAL>(credPtr);
                byte[] passwordBytes = new byte[cred.CredentialBlobSize];
                Marshal.Copy(cred.CredentialBlob, passwordBytes, 0, cred.CredentialBlobSize);
                return Encoding.Unicode.GetString(passwordBytes);
            }
            finally {
                CredFree(credPtr);
            }
        }
    }
"@

    return [CredentialManager]::GetCredential($CREDENTIAL_TARGET)
}

# Get credentials - try WSL first, then Windows Credential Manager
Write-Host "[AUTH] Retrieving Claude Code credentials..." -ForegroundColor Yellow
$credentialJson = $null

# First, try to get credentials from WSL
Write-Host "[WSL] Checking WSL for Claude Code credentials..." -ForegroundColor Cyan
$credentialJson = Get-ClaudeCredentialsFromWSL

# If WSL fails, try Windows Credential Manager
if (-not $credentialJson) {
    Write-Host "[WIN] Checking Windows Credential Manager..." -ForegroundColor Cyan
    $credentialJson = Get-ClaudeCredentials
}

if (-not $credentialJson) {
    Write-Host "[ERROR] No Claude Code credentials found!" -ForegroundColor Red
    Write-Host "" -ForegroundColor White
    Write-Host "If you are using Claude Code in WSL environment:" -ForegroundColor Yellow
    Write-Host "1. Login to Claude Code in WSL: claude-code auth login" -ForegroundColor White
    Write-Host "2. Or ensure credentials are saved at: ~/.claude/.credentials.json" -ForegroundColor White
    Write-Host "" -ForegroundColor White
    Write-Host "If you are using Windows environment:" -ForegroundColor Yellow
    Write-Host "1. Login to Claude Code" -ForegroundColor White
    Write-Host "2. Ensure credentials are stored in Windows Credential Manager as: '$CREDENTIAL_TARGET'" -ForegroundColor White
    exit 1
}

try {
    $credentials = $credentialJson | ConvertFrom-Json
    $accessToken = $credentials.claudeAiOauth.accessToken
    $refreshToken = $credentials.claudeAiOauth.refreshToken
    $expiresAt = $credentials.claudeAiOauth.expiresAt
}
catch {
    Write-Host "[ERROR] Failed to parse credentials JSON: $_" -ForegroundColor Red
    exit 1
}

# Upload secrets to GitHub
Write-Host "[SECRET] Uploading secrets to $TargetRepo..." -ForegroundColor Yellow

try {
    $accessToken | gh secret set CLAUDE_ACCESS_TOKEN --repo $TargetRepo
    $refreshToken | gh secret set CLAUDE_REFRESH_TOKEN --repo $TargetRepo
    $expiresAt.ToString() | gh secret set CLAUDE_EXPIRES_AT --repo $TargetRepo
    Write-Host "[OK] Secrets uploaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] Failed to upload secrets: $_" -ForegroundColor Red
    exit 1
}

# Clone repository
Write-Host "[CLONE] Cloning repository..." -ForegroundColor Yellow
$GH_CLONE_DIR = Join-Path $TMP_DIR "repo"
gh repo clone $TargetRepo $GH_CLONE_DIR

# Prepare workflow template BEFORE changing directory
$templatePath = Join-Path $ROOT_DIR "templates" "claude.yml"
if (-not (Test-Path $templatePath)) {
    Write-Host "[ERROR] Template file not found at: $templatePath" -ForegroundColor Red
    exit 1
}

# Read template content before changing directory
$templateContent = Get-Content $templatePath -Raw
$workflowContent = $templateContent -replace "OWNER_PLACEHOLDER/claude-code-action@main", $ACTION_REF

# Now change to the cloned repository directory
Push-Location $GH_CLONE_DIR

try {
    # Prepare workflow directory
    $workflowDir = Split-Path -Parent $WORKFLOW_PATH
    if (-not (Test-Path $workflowDir)) {
        New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    }

    # Write the workflow file
    Set-Content $WORKFLOW_PATH $workflowContent -NoNewline

    # Create branch
    $BRANCH = $BRANCH_BASE
    $existingBranch = git ls-remote --heads origin $BRANCH 2>$null
    if ($existingBranch) {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $BRANCH = "${BRANCH_BASE}-${timestamp}"
    }

    Write-Host "[BRANCH] Creating branch: $BRANCH" -ForegroundColor Yellow
    git checkout -b $BRANCH

    # Commit and push
    git add $WORKFLOW_PATH
    $hasChanges = git diff --cached --quiet 2>$null; $LASTEXITCODE -ne 0

    if ($hasChanges) {
        Write-Host "[COMMIT] Committing changes..." -ForegroundColor Yellow
        git commit -m "Add/Update Claude PR Assistant workflow"
        git push -u origin $BRANCH
        
        Write-Host "[PR] Creating pull request..." -ForegroundColor Yellow
        try {
            gh pr create --title "Add Claude PR Assistant" `
                         --body "Adds or updates workflow using $ACTION_REF." `
                         --repo $TargetRepo `
                         --base main | Out-Null
            Write-Host "[OK] Pull request created!" -ForegroundColor Green
        }
        catch {
            Write-Host "[WARN] Could not create PR (it may already exist)" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "[INFO] No changes needed - workflow already up to date" -ForegroundColor Cyan
    }
}
finally {
    # Always return to original directory
    Pop-Location
}

# Cleanup
Remove-Item -Recurse -Force $TMP_DIR

Write-Host "`n[COMPLETE] Repository setup complete!" -ForegroundColor Green
