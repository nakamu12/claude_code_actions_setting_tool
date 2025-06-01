# Claude PR Assistant - Windows Repository Setup Script
param(
    [Parameter(Mandatory=$true)]
    [string]$TargetRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate repository format
if ($TargetRepo -notmatch "^[^/]+/[^/]+$") {
    Write-Host "❌ Invalid repository format. Use: owner/repo" -ForegroundColor Red
    exit 1
}

Write-Host "🚀 Setting up Claude PR Assistant for $TargetRepo..." -ForegroundColor Green

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
        Write-Host "❌ $cmd is not installed. Please install $($requiredCommands[$cmd])" -ForegroundColor Red
        exit 1
    }
}

# Authenticate with gh if needed
try {
    gh auth status | Out-Null
}
catch {
    Write-Host "🔐 Running 'gh auth login'..." -ForegroundColor Yellow
    gh auth login
}

$GH_USER = gh api user --jq .login
$ACTION_REF = "$GH_USER/claude-code-action@main"

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

# Get credentials
Write-Host "🔐 Retrieving credentials from Windows Credential Manager..." -ForegroundColor Yellow
$credentialJson = Get-ClaudeCredentials

if (-not $credentialJson) {
    Write-Host "❌ Credential not found in Windows Credential Manager" -ForegroundColor Red
    Write-Host "Please ensure you have Claude Code credentials stored with target name: $CREDENTIAL_TARGET" -ForegroundColor Yellow
    exit 1
}

try {
    $credentials = $credentialJson | ConvertFrom-Json
    $accessToken = $credentials.claudeAiOauth.accessToken
    $refreshToken = $credentials.claudeAiOauth.refreshToken
    $expiresAt = $credentials.claudeAiOauth.expiresAt
}
catch {
    Write-Host "❌ Failed to parse credentials JSON: $_" -ForegroundColor Red
    exit 1
}

# Upload secrets to GitHub
Write-Host "🔐 Uploading secrets to $TargetRepo..." -ForegroundColor Yellow

try {
    $accessToken | gh secret set CLAUDE_ACCESS_TOKEN --repo $TargetRepo
    $refreshToken | gh secret set CLAUDE_REFRESH_TOKEN --repo $TargetRepo
    $expiresAt.ToString() | gh secret set CLAUDE_EXPIRES_AT --repo $TargetRepo
    Write-Host "✔️  Secrets uploaded successfully" -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to upload secrets: $_" -ForegroundColor Red
    exit 1
}

# Clone repository
Write-Host "📁 Cloning repository..." -ForegroundColor Yellow
$GH_CLONE_DIR = Join-Path $TMP_DIR "repo"
gh repo clone $TargetRepo $GH_CLONE_DIR
Set-Location $GH_CLONE_DIR

# Prepare workflow
$workflowDir = Split-Path -Parent $WORKFLOW_PATH
if (-not (Test-Path $workflowDir)) {
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
}

$templatePath = Join-Path $ROOT_DIR "templates" "claude.yml"
if (-not (Test-Path $templatePath)) {
    Write-Host "❌ Template file not found at: $templatePath" -ForegroundColor Red
    exit 1
}

Copy-Item $templatePath $WORKFLOW_PATH -Force

# Replace placeholder in workflow
$content = Get-Content $WORKFLOW_PATH -Raw
$content = $content -replace "OWNER_PLACEHOLDER/claude-code-action@main", $ACTION_REF
Set-Content $WORKFLOW_PATH $content -NoNewline

# Create branch
$BRANCH = $BRANCH_BASE
$existingBranch = git ls-remote --heads origin $BRANCH 2>$null
if ($existingBranch) {
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $BRANCH = "${BRANCH_BASE}-${timestamp}"
}

Write-Host "🌿 Creating branch: $BRANCH" -ForegroundColor Yellow
git checkout -b $BRANCH

# Commit and push
git add $WORKFLOW_PATH
$hasChanges = git diff --cached --quiet 2>$null; $LASTEXITCODE -ne 0

if ($hasChanges) {
    Write-Host "📝 Committing changes..." -ForegroundColor Yellow
    git commit -m "Add/Update Claude PR Assistant workflow"
    git push -u origin $BRANCH
    
    Write-Host "🔄 Creating pull request..." -ForegroundColor Yellow
    try {
        gh pr create --title "Add Claude PR Assistant" `
                     --body "Adds or updates workflow using $ACTION_REF." `
                     --repo $TargetRepo `
                     --base main | Out-Null
        Write-Host "✔️  Pull request created!" -ForegroundColor Green
    }
    catch {
        Write-Host "⚠️  Could not create PR (it may already exist)" -ForegroundColor Yellow
    }
}
else {
    Write-Host "ℹ️  No changes needed - workflow already up to date" -ForegroundColor Cyan
}

# Cleanup
Set-Location $SCRIPT_DIR
Remove-Item -Recurse -Force $TMP_DIR

Write-Host "`n✅ Repository setup complete!" -ForegroundColor Green