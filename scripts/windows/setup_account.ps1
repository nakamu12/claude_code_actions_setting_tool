# Claude PR Assistant - Windows Setup Account Script
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "[SETUP] Setting up Claude Code Actions for your GitHub account..." -ForegroundColor Green

# Ensure GitHub CLI is installed
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "[INSTALL] GitHub CLI not found. Installing..." -ForegroundColor Yellow
    
    # Try winget first
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing via winget..."
        winget install --id GitHub.cli --accept-package-agreements --accept-source-agreements
    }
    # Try Chocolatey
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Installing via Chocolatey..."
        choco install gh -y
    }
    else {
        Write-Host "[ERROR] Please install GitHub CLI manually from: https://cli.github.com/manual/installation" -ForegroundColor Red
        Write-Host "After installation, run this script again." -ForegroundColor Yellow
        exit 1
    }
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Authenticate if needed
try {
    gh auth status | Out-Null
}
catch {
    Write-Host "[AUTH] Running 'gh auth login'..." -ForegroundColor Yellow
    gh auth login
}

# Get current user
$GH_USER = gh api user --jq .login

# Fork required repositories
$REPOS_TO_FORK = @(
    "grll/claude-code-action",
    "grll/claude-code-base-action"
)

foreach ($SOURCE in $REPOS_TO_FORK) {
    $REPO_NAME = Split-Path $SOURCE -Leaf
    $DEST = "$GH_USER/$REPO_NAME"
    
    try {
        gh repo view $DEST | Out-Null
        Write-Host "[OK] Fork exists: $DEST" -ForegroundColor Green
    }
    catch {
        Write-Host "[FORK] Forking $SOURCE -> $DEST..." -ForegroundColor Yellow
        try {
            gh repo fork $SOURCE --clone=false --fork-name=$REPO_NAME
            Write-Host "[OK] Successfully forked!" -ForegroundColor Green
        }
        catch {
            Write-Host "[ERROR] Fork failed for $SOURCE" -ForegroundColor Red
            exit 1
        }
    }
}

Write-Host "`n[INFO] Action reference will be: $GH_USER/claude-code-action@main" -ForegroundColor Cyan

# Claude GitHub App installation (manual step)
$APP_SLUG = "claude"
$INSTALL_URL = "https://github.com/apps/$APP_SLUG"

Write-Host "`n[MANUAL] Manual Step Required:" -ForegroundColor Yellow
Write-Host "Please ensure the Claude GitHub App is installed to your account/organization." -ForegroundColor White
Write-Host "Visit: $INSTALL_URL" -ForegroundColor Cyan
Write-Host "Note: App installation check is skipped to avoid authentication issues." -ForegroundColor Gray

Write-Host "`n[COMPLETE] setup_account complete!" -ForegroundColor Green
Write-Host "Next step: Run setup_repository.ps1 <owner/repo> for each repository" -ForegroundColor Cyan