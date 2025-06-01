@echo off
setlocal enabledelayedexpansion

rem Usage: setup_repository.bat <owner/repo>
if "%~1"=="" (
    echo Usage: %0 ^<owner/repo^> >&2
    exit /b 1
)
set "TARGET_REPO=%~1"

set "KEYCHAIN_SERVICE_NAME=Claude Code-credentials"
set "SCRIPT_DIR=%~dp0"
for %%i in ("%SCRIPT_DIR%..\..") do set "ROOT_DIR=%%~fi"
set "TMP_DIR=%TEMP%\claude_setup_%RANDOM%"
set "WORKFLOW_PATH=.github\workflows\claude.yml"
set "BRANCH_BASE=setup-claude-pr-action"

rem Create temp directory  
mkdir "%TMP_DIR%" 2>nul

rem Ensure required commands (equivalent to Mac's for loop with auto-install)
for %%c in (jq gh git) do (
    where %%c >nul 2>&1 || (
        echo 📦 installing %%c
        call :InstallTool %%c
        if errorlevel 1 (
            echo Failed to install %%c. Please install manually.
            exit /b 1
        )
        rem Refresh PATH to ensure newly installed tool is available
        call :RefreshPath
        where %%c >nul 2>&1 || (
            echo %c% was installed but not found in PATH. Please restart command prompt.
            exit /b 1
        )
    )
)

rem gh login if needed
gh auth status >nul 2>&1 || gh auth login

rem Get GitHub user
for /f "tokens=*" %%i in ('gh api user --jq .login') do set "GH_USER=%%i"
set "ACTION_REF=%GH_USER%/claude-code-action@main"

rem Extract tokens (equivalent to Mac's security command)
call :GetCredentials
if "%RAW%"=="" (
    echo Keychain entry not found >&2
    exit /b 1
)

rem Parse JSON tokens (equivalent to Mac's echo "$RAW" | jq)
for /f "tokens=*" %%i in ('echo %RAW% ^| jq -r ".claudeAiOauth.accessToken"') do set "ACC=%%i"
for /f "tokens=*" %%i in ('echo %RAW% ^| jq -r ".claudeAiOauth.refreshToken"') do set "REF=%%i"
for /f "tokens=*" %%i in ('echo %RAW% ^| jq -r ".claudeAiOauth.expiresAt"') do set "EXP=%%i"

echo 🔐 Uploading secrets …
gh secret set CLAUDE_ACCESS_TOKEN --body "%ACC%" --repo "%TARGET_REPO%"
gh secret set CLAUDE_REFRESH_TOKEN --body "%REF%" --repo "%TARGET_REPO%"
gh secret set CLAUDE_EXPIRES_AT --body "%EXP%" --repo "%TARGET_REPO%"

rem Clone repo
set "GH_CLONE_DIR=%TMP_DIR%\repo"
gh repo clone "%TARGET_REPO%" "%GH_CLONE_DIR%"
cd /d "%GH_CLONE_DIR%"

rem Prepare workflow (equivalent to Mac's mkdir -p and cp)
if not exist ".github\workflows" mkdir ".github\workflows"
copy "%ROOT_DIR%\templates\claude.yml" "%WORKFLOW_PATH%" >nul

rem Replace placeholder (equivalent to Mac's sed)
powershell -Command "(Get-Content '%WORKFLOW_PATH%') -replace 'OWNER_PLACEHOLDER/claude-code-action@main', '%ACTION_REF%' | Set-Content '%WORKFLOW_PATH%'"

rem Branch handling
set "BRANCH=%BRANCH_BASE%"
git ls-remote --exit-code --heads origin "%BRANCH%" >nul 2>&1
if not errorlevel 1 (
    rem Branch exists, create timestamped version (equivalent to Mac's date +%%Y%%m%%d%%H%%M%%S)
    for /f "tokens=2 delims== " %%i in ('wmic OS Get localdatetime /value ^| find "="') do (
        set "datetime=%%i"
        set "BRANCH=%BRANCH_BASE%-!datetime:~0,14!"
    )
)

git checkout -b "%BRANCH%"
git add "%WORKFLOW_PATH%"

rem Check if there are changes to commit (equivalent to Mac's if ! git diff --cached --quiet)
git diff --cached --quiet
if errorlevel 1 (
    git commit -m "Add/Update Claude PR Assistant workflow"
    git push -u origin "%BRANCH%"
    rem Create PR (equivalent to Mac's || true for error ignoring)
    gh pr create --title "Add Claude PR Assistant" --body "Adds or updates workflow using %ACTION_REF%." --repo "%TARGET_REPO%" --base main >nul 2>&1 || echo >nul
)

rem Cleanup
cd /d "%SCRIPT_DIR%"
rmdir /s /q "%TMP_DIR%" 2>nul
goto :eof

:GetCredentials
rem Windows equivalent of Mac's security find-generic-password
powershell -Command "& {try {Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; using System.Text; public class CredentialManager { [DllImport(\"advapi32.dll\", SetLastError=true, CharSet=CharSet.Unicode)] private static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr); [DllImport(\"advapi32.dll\", SetLastError=true)] private static extern bool CredFree([In] IntPtr cred); [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] private struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; } public static string GetCredential(string target) { IntPtr credPtr; if (!CredRead(target, 1, 0, out credPtr)) { return null; } try { CREDENTIAL cred = Marshal.PtrToStructure<CREDENTIAL>(credPtr); byte[] passwordBytes = new byte[cred.CredentialBlobSize]; Marshal.Copy(cred.CredentialBlob, passwordBytes, 0, cred.CredentialBlobSize); return Encoding.Unicode.GetString(passwordBytes); } finally { CredFree(credPtr); } } }'; $result = [CredentialManager]::GetCredential('%KEYCHAIN_SERVICE_NAME%'); if ($result) { Write-Output $result } else { Write-Output '' } } catch { Write-Output '' }}" > "%TMP_DIR%\cred.txt"

set /p RAW=<"%TMP_DIR%\cred.txt"

rem If Windows Credential Manager fails, try WSL (alternative source)
if "%RAW%"=="" (
    wsl test -f ~/.claude/.credentials.json 2>nul && (
        for /f "usebackq delims=" %%i in (`wsl cat ~/.claude/.credentials.json 2^>nul`) do set "RAW=%%i"
    )
    if "!RAW!"=="" (
        wsl test -f ~/.config/claude/credentials.json 2>nul && (
            for /f "usebackq delims=" %%i in (`wsl cat ~/.config/claude/credentials.json 2^>nul`) do set "RAW=%%i"
        )
    )
)
goto :eof

:InstallTool
set "tool=%~1"

rem Try winget first (Windows Package Manager)
if "%tool%"=="jq" (
    winget install jqlang.jq --silent >nul 2>&1
    if not errorlevel 1 (
        echo Successfully installed jq via winget
        exit /b 0
    )
)

if "%tool%"=="gh" (
    winget install GitHub.cli --silent >nul 2>&1
    if not errorlevel 1 (
        echo Successfully installed GitHub CLI via winget
        exit /b 0
    )
)

if "%tool%"=="git" (
    winget install Git.Git --silent >nul 2>&1
    if not errorlevel 1 (
        echo Successfully installed Git via winget
        exit /b 0
    )
)

rem Try chocolatey as fallback
where choco >nul 2>&1 && (
    echo Trying chocolatey...
    if "%tool%"=="jq" choco install jq -y >nul 2>&1
    if "%tool%"=="gh" choco install gh -y >nul 2>&1
    if "%tool%"=="git" choco install git -y >nul 2>&1
    
    where %tool% >nul 2>&1 && (
        echo Successfully installed %tool% via chocolatey
        exit /b 0
    )
)

rem Try scoop as fallback
where scoop >nul 2>&1 && (
    echo Trying scoop...
    if "%tool%"=="jq" scoop install jq >nul 2>&1
    if "%tool%"=="gh" scoop install gh >nul 2>&1
    if "%tool%"=="git" scoop install git >nul 2>&1
    
    where %tool% >nul 2>&1 && (
        echo Successfully installed %tool% via scoop
        exit /b 0
    )
)

rem If all package managers fail, provide manual instructions
echo Failed to auto-install %tool%. Please install manually:
if "%tool%"=="jq" echo - Download from: https://jqlang.github.io/jq/download/
if "%tool%"=="gh" echo - Download from: https://cli.github.com/
if "%tool%"=="git" echo - Download from: https://git-scm.com/
echo Or install a package manager like winget, chocolatey, or scoop
exit /b 1

:RefreshPath
rem Refresh PATH environment variable to pick up newly installed tools
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SysPath=%%b"
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set "UserPath=%%b"
if defined UserPath (
    set "PATH=%SysPath%;%UserPath%"
) else (
    set "PATH=%SysPath%"
)
exit /b 0
