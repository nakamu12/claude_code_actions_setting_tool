# PowerShell script to update Claude OAuth tokens for a repository
# This script refreshes tokens to prevent expiration

param(
    [Parameter(Mandatory=$false)]
    [string]$Repository,
    [switch]$Help
)

if ($Help -or [string]::IsNullOrEmpty($Repository)) {
    Write-Host @"
Usage: .\update_token.ps1 -Repository <owner/repo>

Example: .\update_token.ps1 -Repository myusername/myproject

This script updates Claude OAuth tokens for a repository by:
1. Retrieving current tokens from Windows Credential Manager
2. Updating the repository secrets with new token values

This should be run periodically (e.g., via Task Scheduler) to refresh tokens.

Prerequisites:
- GitHub CLI authenticated
- Claude OAuth tokens in Windows Credential Manager
- Repository already set up with setup_repository.ps1
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
        return $null
    }

    try {
        # Parse the JSON credential data
        $credentials = $credentialData | ConvertFrom-Json
        return $credentials
    } catch {
        return $null
    }
}

Write-Host "Updating Claude tokens for repository: $Repository" -ForegroundColor Green

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

# Update secrets in repository
Write-Host "Updating repository secrets..." -ForegroundColor Yellow

$secrets = @{
    "CLAUDE_ACCESS_TOKEN" = $accessToken
    "CLAUDE_REFRESH_TOKEN" = $refreshToken
    "CLAUDE_EXPIRES_AT" = $expiresAt
}

$updateCount = 0
foreach ($secretName in $secrets.Keys) {
    Write-Host "Updating secret: $secretName" -ForegroundColor Cyan
    $secrets[$secretName] | gh secret set $secretName --repo $Repository
    if ($LASTEXITCODE -eq 0) {
        $updateCount++
    } else {
        Write-Host "Failed to update secret: $secretName" -ForegroundColor Red
    }
}

if ($updateCount -eq 3) {
    Write-Host "`nSuccessfully updated all tokens!" -ForegroundColor Green
    
    # Log update time for reference
    $logFile = Join-Path $env:USERPROFILE ".claude-token-updates.log"
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - Updated tokens for $Repository"
    Add-Content -Path $logFile -Value $logEntry
    
} else {
    Write-Host "`nSome tokens failed to update" -ForegroundColor Red
    exit 1
}

# Optional: Check token expiration
if ($expiresAt) {
    try {
        $expiryDate = [DateTimeOffset]::FromUnixTimeSeconds($expiresAt).LocalDateTime
        $daysUntilExpiry = ($expiryDate - (Get-Date)).Days
        
        if ($daysUntilExpiry -lt 7) {
            Write-Host "`nWARNING: Token expires in $daysUntilExpiry days ($expiryDate)" -ForegroundColor Yellow
            Write-Host "Consider refreshing your Claude Code login soon" -ForegroundColor Yellow
        } else {
            Write-Host "Token expires in $daysUntilExpiry days ($expiryDate)" -ForegroundColor Cyan
        }
    } catch {
        # Ignore if we can't parse the expiry date
    }
}