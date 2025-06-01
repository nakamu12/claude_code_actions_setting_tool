# PowerShell script to set up Claude Code Action for Windows
# This script performs initial account-level setup

param(
    [switch]$Help
)

if ($Help) {
    Write-Host @"
Usage: .\setup_account.ps1

This script sets up your GitHub account to use Claude PR Assistant by:
1. Installing GitHub CLI if not present
2. Authenticating with GitHub
3. Forking required action repositories
4. Ensuring Claude app is installed

Prerequisites:
- Windows PowerShell 5.1 or PowerShell Core 7+
- Internet connection
- GitHub account
"@
    exit 0
}

Write-Host "Setting up Claude Code Action for your GitHub account..." -ForegroundColor Green

# Check if running as administrator (recommended for Chocolatey)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# Function to install GitHub CLI
function Install-GitHubCLI {
    # Check if gh is already installed
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        Write-Host "GitHub CLI is already installed" -ForegroundColor Yellow
        return
    }

    Write-Host "Installing GitHub CLI..." -ForegroundColor Yellow
    
    # Try winget first (Windows 11 and some Windows 10)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing via winget..."
        winget install --id GitHub.cli -e --source winget
    }
    # Try Chocolatey if available
    elseif (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Host "Installing via Chocolatey..."
        choco install gh -y
    }
    # Manual download as fallback
    else {
        Write-Host "Please install GitHub CLI manually from: https://cli.github.com/manual/installation" -ForegroundColor Red
        Write-Host "After installation, run this script again." -ForegroundColor Red
        exit 1
    }
    
    # Refresh PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# Install GitHub CLI if needed
Install-GitHubCLI

# Check if gh is now available
if (!(Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Host "GitHub CLI installation failed. Please install manually." -ForegroundColor Red
    exit 1
}

# Authenticate with GitHub if not already authenticated
Write-Host "Checking GitHub authentication..." -ForegroundColor Yellow
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Please authenticate with GitHub:" -ForegroundColor Yellow
    gh auth login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "GitHub authentication failed" -ForegroundColor Red
        exit 1
    }
}

Write-Host "GitHub authentication successful" -ForegroundColor Green

# Get current user
$currentUser = gh api user --jq .login
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to get current user" -ForegroundColor Red
    exit 1
}

Write-Host "Logged in as: $currentUser" -ForegroundColor Cyan

# Fork required repositories
$reposToFork = @(
    "grll/claude-code-action",
    "grll/claude-code-base-action"
)

foreach ($repo in $reposToFork) {
    Write-Host "Checking fork of $repo..." -ForegroundColor Yellow
    
    # Check if fork already exists
    $forkName = $repo.Split('/')[1]
    $forkExists = gh repo view "$currentUser/$forkName" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Fork already exists: $currentUser/$forkName" -ForegroundColor Green
    } else {
        Write-Host "Creating fork of $repo..." -ForegroundColor Yellow
        gh repo fork $repo --clone=false
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to fork $repo" -ForegroundColor Red
            exit 1
        }
        Write-Host "Successfully forked: $currentUser/$forkName" -ForegroundColor Green
    }
}

# Check if Claude app is installed
Write-Host "`nChecking Claude app installation..." -ForegroundColor Yellow
Write-Host "Please ensure the Claude app is installed on your GitHub account." -ForegroundColor Cyan
Write-Host "Visit: https://github.com/apps/claude" -ForegroundColor Cyan

$openBrowser = Read-Host "Would you like to open the Claude app page in your browser? (y/n)"
if ($openBrowser -eq 'y' -or $openBrowser -eq 'Y') {
    Start-Process "https://github.com/apps/claude"
}

Write-Host "`nAccount setup completed!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Ensure you have OAuth tokens from Claude Code (stored in Windows Credential Manager)"
Write-Host "2. Run setup_repository.ps1 for each repository you want to enable"
Write-Host "3. Optionally set up scheduled task to run update_token.ps1 periodically"