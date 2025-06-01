# PowerShell script to set up Claude Code Action for a specific repository
# This script configures a repository to use Claude PR Assistant

param(
    [Parameter(Mandatory=$false)]
    [string]$Repository,
    [switch]$Help
)

if ($Help -or [string]::IsNullOrEmpty($Repository)) {
    Write-Host @"
Usage: .\setup_repository.ps1 -Repository <owner/repo>

Example: .\setup_repository.ps1 -Repository myusername/myproject

This script sets up a specific repository to use Claude PR Assistant by:
1. Retrieving OAuth tokens from Windows Credential Manager
2. Adding tokens as GitHub secrets
3. Cloning the repository
4. Adding the Claude workflow
5. Creating a pull request

Prerequisites:
- GitHub CLI authenticated (run setup_account.ps1 first)
- Claude OAuth tokens stored in Windows Credential Manager
- Write access to the target repository
"@
    exit 0
}

# Function to get credentials from Windows Credential Manager
function Get-ClaudeCredentials {
    Add-Type -AssemblyName System.Runtime.InteropServices
    
    $source = @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class CredentialManager
{
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool CredFree([In] IntPtr cred);

    private const int CRED_TYPE_GENERIC = 1;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
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

    public static string GetCredential(string target)
    {
        IntPtr credPtr;
        if (!CredRead(target, CRED_TYPE_GENERIC, 0, out credPtr))
        {
            return null;
        }

        try
        {
            CREDENTIAL cred = (CREDENTIAL)Marshal.PtrToStructure(credPtr, typeof(CREDENTIAL));
            byte[] passwordBytes = new byte[cred.CredentialBlobSize];
            Marshal.Copy(cred.CredentialBlob, passwordBytes, 0, cred.CredentialBlobSize);
            return Encoding.Unicode.GetString(passwordBytes);
        }
        finally
        {
            CredFree(credPtr);
        }
    }
}
"@

    if (-not ([System.Management.Automation.PSTypeName]'CredentialManager').Type) {
        Add-Type -TypeDefinition $source -Language CSharp
    }

    # Try to get credentials from Windows Credential Manager
    $credentialName = "Claude Code-credentials"
    $credentialData = [CredentialManager]::GetCredential($credentialName)
    
    if ($null -eq $credentialData) {
        Write-Host "Claude credentials not found in Windows Credential Manager" -ForegroundColor Red
        Write-Host "Please ensure you have signed in to Claude Code and credentials are stored" -ForegroundColor Yellow
        return $null
    }

    try {
        # Parse the JSON credential data
        $credentials = $credentialData | ConvertFrom-Json
        return $credentials
    } catch {
        Write-Host "Failed to parse credential data" -ForegroundColor Red
        return $null
    }
}

Write-Host "Setting up Claude Code Action for repository: $Repository" -ForegroundColor Green

# Check if gh is authenticated
$authStatus = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "Not authenticated with GitHub. Please run setup_account.ps1 first." -ForegroundColor Red
    exit 1
}

# Get Claude credentials
Write-Host "Retrieving Claude credentials from Windows Credential Manager..." -ForegroundColor Yellow
$credentials = Get-ClaudeCredentials

if ($null -eq $credentials) {
    Write-Host "Failed to retrieve Claude credentials" -ForegroundColor Red
    Write-Host "Please ensure you have signed in to Claude Code and try again" -ForegroundColor Yellow
    exit 1
}

# Extract tokens
$accessToken = $credentials.accessToken
$refreshToken = $credentials.refreshToken
$expiresAt = $credentials.expiresAt

if ([string]::IsNullOrEmpty($accessToken) -or [string]::IsNullOrEmpty($refreshToken)) {
    Write-Host "Invalid credentials format" -ForegroundColor Red
    exit 1
}

Write-Host "Successfully retrieved Claude credentials" -ForegroundColor Green

# Add secrets to repository
Write-Host "Adding secrets to repository..." -ForegroundColor Yellow

$secrets = @{
    "CLAUDE_ACCESS_TOKEN" = $accessToken
    "CLAUDE_REFRESH_TOKEN" = $refreshToken
    "CLAUDE_EXPIRES_AT" = $expiresAt
}

foreach ($secretName in $secrets.Keys) {
    Write-Host "Setting secret: $secretName" -ForegroundColor Cyan
    $secrets[$secretName] | gh secret set $secretName --repo $Repository
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to set secret: $secretName" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Successfully added all secrets" -ForegroundColor Green

# Create temporary directory for cloning
$tempDir = Join-Path $env:TEMP "claude-setup-$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null

Push-Location $tempDir
try {
    # Clone the repository
    Write-Host "Cloning repository..." -ForegroundColor Yellow
    gh repo clone $Repository
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to clone repository" -ForegroundColor Red
        exit 1
    }

    # Navigate to repository
    $repoName = $Repository.Split('/')[1]
    Set-Location $repoName

    # Create .github/workflows directory if it doesn't exist
    $workflowDir = ".github/workflows"
    if (!(Test-Path $workflowDir)) {
        New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    }

    # Get current user
    $currentUser = gh api user --jq .login

    # Create workflow file with user's fork
    $workflowContent = @"
name: Claude PR Assistant

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened]
  pull_request:
    types: [opened]
  pull_request_review:
    types: [submitted]

permissions:
  issues: write
  pull-requests: write
  contents: write

jobs:
  claude-code:
    # Only run when authorized users mention @claude
    if: |
      (
        contains(github.event.comment.body, '@claude') || 
        contains(github.event.issue.body, '@claude') || 
        contains(github.event.pull_request.body, '@claude') ||
        contains(github.event.review.body, '@claude')
      ) &&
      (
        github.event.comment.author_association == 'OWNER' ||
        github.event.comment.author_association == 'COLLABORATOR' ||
        github.event.comment.author_association == 'MEMBER' ||
        github.event.issue.author_association == 'OWNER' ||
        github.event.issue.author_association == 'COLLABORATOR' ||
        github.event.issue.author_association == 'MEMBER' ||
        github.event.pull_request.author_association == 'OWNER' ||
        github.event.pull_request.author_association == 'COLLABORATOR' ||
        github.event.pull_request.author_association == 'MEMBER' ||
        github.event.review.author_association == 'OWNER' ||
        github.event.review.author_association == 'COLLABORATOR' ||
        github.event.review.author_association == 'MEMBER'
      )
    runs-on: ubuntu-latest
    
    steps:
      - uses: $currentUser/claude-code-action@main
        with:
          provider: oauth
          oauth-access-token: `${{ secrets.CLAUDE_ACCESS_TOKEN }}
          oauth-refresh-token: `${{ secrets.CLAUDE_REFRESH_TOKEN }}
          oauth-expires-at: `${{ secrets.CLAUDE_EXPIRES_AT }}
"@

    # Write workflow file
    $workflowPath = Join-Path $workflowDir "claude.yml"
    $workflowContent | Out-File -FilePath $workflowPath -Encoding UTF8

    # Create new branch
    $branchName = "add-claude-workflow-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    git checkout -b $branchName

    # Commit changes
    git add .
    git commit -m "Add Claude PR Assistant workflow

This workflow enables Claude AI to assist with pull requests and issues
when mentioned with @claude by authorized users."

    # Push branch
    git push origin $branchName

    # Create pull request
    Write-Host "Creating pull request..." -ForegroundColor Yellow
    $prBody = @"
This PR adds the Claude PR Assistant workflow to enable AI assistance for issues and pull requests.

## What this does
- Responds to @claude mentions in issues and pull requests
- Only authorized users (owners, collaborators, members) can trigger Claude
- Uses OAuth authentication with Claude

## Prerequisites completed
- Claude OAuth tokens have been added as repository secrets
- Required action repositories have been forked

## Next steps
After merging this PR:
1. Test by creating an issue and mentioning @claude
2. Set up token refresh (optional but recommended)
"@

    gh pr create `
        --title "Add Claude PR Assistant workflow" `
        --body $prBody `
        --base main `
        --head $branchName

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Pull request created successfully!" -ForegroundColor Green
    } else {
        Write-Host "Failed to create pull request" -ForegroundColor Red
        Write-Host "You can manually create it from branch: $branchName" -ForegroundColor Yellow
    }

} finally {
    Pop-Location
    # Clean up temporary directory
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`nRepository setup completed!" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Review and merge the pull request"
Write-Host "2. Test by mentioning @claude in an issue or PR"
Write-Host "3. Consider setting up automatic token refresh with update_token.ps1"