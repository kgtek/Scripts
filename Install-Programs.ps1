<#
.SYNOPSIS
    Silently installs a predefined list of programs via winget, then
    downloads and runs Install-Office365Business.ps1 from GitHub.

.DESCRIPTION
    Designed for unattended deployment via Syncro RMM. All output goes to
    Write-Output so it appears in Syncro's script run log. No progress bars
    or colored output â use Install-Programs-Local.ps1 for interactive runs.

.NOTES
    SYNCRO SETUP:
      No script variables required. Run as SYSTEM (Syncro default).
      Internet access required.
      Increase script timeout to 30+ minutes to accommodate Office install.

    - Exit code 0 = everything succeeded
    - Exit code 1 = one or more steps failed (Syncro will flag this)
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$script:Errors = 0

# =============================================================================
# PROGRAM LIST â winget Package IDs
# Find IDs at: https://winget.run  or run: winget search <name>
# Office 365 is handled separately at the end via GitHub download.
# =============================================================================
$Programs = @(
    "Mozilla.Firefox"                 # Mozilla Firefox
    "Google.Chrome"                   # Google Chrome
    "7zip.7zip"                       # 7-Zip
    "VideoLAN.VLC"                    # VLC Media Player
    "Adobe.Acrobat.Reader.64-bit"     # Adobe Acrobat Reader (64-bit)
)
# =============================================================================

$Office365ScriptUrl = "https://raw.githubusercontent.com/kgtek/Scripts/main/Install-Office365Business.ps1"

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output "--- $Message ---"
}

Write-Output "Program Installation Script (Syncro)"
Write-Output "Computer: $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Programs queued: $($Programs.Count) via winget + Office 365 via GitHub"

Write-Step "Step 1: Checking winget availability"

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    $wingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" `
        -ErrorAction SilentlyContinue | Select-Object -Last 1 -ExpandProperty Path
    if ($wingetPath) {
        Set-Alias winget $wingetPath -Scope Script
        Write-Output "  winget found at: $wingetPath"
    } else {
        Write-Output "  FAILED: winget not found on $env:COMPUTERNAME."
        exit 1
    }
} else {
    Write-Output "  winget found: $($winget.Source)"
}

Write-Step "Step 2: Installing programs via winget"

$total = $Programs.Count
$current = 0

foreach ($PackageId in $Programs) {
    $current++
    Write-Output ""
    Write-Output "  [$current/$total] Installing: $PackageId"

    $installed = winget list --id $PackageId --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0 -and ($installed -match $PackageId)) {
        Write-Output "  SKIPPED: $PackageId already installed."
        continue
    }

    $result = winget install `
        --id $PackageId --exact --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Output "  SUCCESS: $PackageId installed."
    } elseif ($LASTEXITCODE -eq -1978335189) {
        Write-Output "  SKIPPED: $PackageId already installed (winget code -1978335189)."
    } else {
        Write-Output "  FAILED: $PackageId â exit code $LASTEXITCODE"
        Write-Output "  Output: $result"
        $script:Errors++
    }
}

Write-Step "Step 3: Downloading and running Office 365 Business installer from GitHub"

$TempOfficeScript = "$env:TEMP\Install-Office365Business.ps1"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Office365ScriptUrl -OutFile $TempOfficeScript -UseBasicParsing -ErrorAction Stop
    Write-Output "  Download successful. Running installer (10-20 min)..."
} catch {
    Write-Output "  FAILED: Could not download Office script â $($_.Exception.Message)"
    $script:Errors++
}

if (Test-Path $TempOfficeScript) {
    try {
        & $TempOfficeScript
        if ($LASTEXITCODE -eq 0) {
            Write-Output "  SUCCESS: Office 365 Business installation complete."
        } else {
            Write-Output "  FAILED: Office installer exited with code $LASTEXITCODE."
            $script:Errors++
        }
    } catch {
        Write-Output "  FAILED: Office installer error â $($_.Exception.Message)"
        $script:Errors++
    }
    Remove-Item -Path $TempOfficeScript -Force -ErrorAction SilentlyContinue
}

Write-Output ""
if ($script:Errors -gt 0) {
    Write-Output "Completed with $($script:Errors) failure(s) on $env:COMPUTERNAME."
    Write-Output "Review output above for details."
    exit 1
} else {
    Write-Output "All installations completed successfully on $env:COMPUTERNAME."
    Write-Output "User must sign in to Microsoft 365 to activate Office."
    exit 0
}
