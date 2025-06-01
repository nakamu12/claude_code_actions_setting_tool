# Claude PR Assistant - Windows Token Update Script
param(
    [Parameter(Mandatory=$true)]
    [string]$GitHubRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate repository format
if ($GitHubRepo -notmatch "^[^/]+/[^/]+$") {
    Write-Host "❌ Invalid repository format. Use: owner/repo" -ForegroundColor Red
    exit 1
}

$CREDENTIAL_TARGET = "Claude Code-credentials"

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

Write-Host "🔄 Updating Claude tokens for $GitHubRepo..." -ForegroundColor Green

# Get credentials from Windows Credential Manager
$credentialJson = Get-ClaudeCredentials

if (-not $credentialJson) {
    Write-Host "❌ Credential '$CREDENTIAL_TARGET' not found in Windows Credential Manager." -ForegroundColor Red
    Write-Host "Please ensure you have Claude Code credentials stored." -ForegroundColor Yellow
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

# Ensure gh is authenticated
try {
    gh auth status | Out-Null
}
catch {
    Write-Host "❌ GitHub CLI is not authenticated. Run 'gh auth login' first." -ForegroundColor Red
    exit 1
}

# Update secrets
Write-Host "🔐 Updating secrets on $GitHubRepo..." -ForegroundColor Yellow

try {
    $accessToken | gh secret set CLAUDE_ACCESS_TOKEN --repo $GitHubRepo
    $refreshToken | gh secret set CLAUDE_REFRESH_TOKEN --repo $GitHubRepo
    $expiresAt.ToString() | gh secret set CLAUDE_EXPIRES_AT --repo $GitHubRepo
    
    Write-Host "✅ Secrets updated successfully." -ForegroundColor Green
}
catch {
    Write-Host "❌ Failed to update secrets: $_" -ForegroundColor Red
    exit 1
}