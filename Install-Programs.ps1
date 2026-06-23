<#
.SYNOPSIS
    Silently installs a predefined list of programs via winget.

.DESCRIPTION
    Installs each program in the $Programs list using winget with silent,
    non-interactive flags. Skips programs already installed. Logs each
    result and exits with code 0 (all success) or 1 (one or more failed).

.NOTES
    SYNCRO SETUP:
      No script variables required. Run as SYSTEM (Syncro default).
      Internet access is required â winget pulls installers from the web.

    TO CUSTOMIZE THE PROGRAM LIST:
      Edit the $Programs array below. Each entry is a winget Package ID.
      Find IDs by running:  winget search <program name>
      or browse https://winget.run

    REQUIREMENTS:
      - Windows 10 1809+ or Windows 11 (winget is built in)
      - On older Win10 builds, winget may need to be installed via the
        App Installer package from the Microsoft Store.

    - Exit code 0 = all installs succeeded (or were already installed)
    - Exit code 1 = one or more installs failed (Syncro will flag this)
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$script:Errors = 0

# =============================================================================
# PROGRAM LIST â Add or remove winget Package IDs here
# Find IDs at: https://winget.run  or run: winget search <name>
# =============================================================================
$Programs = @(
    "Mozilla.Firefox"                 # Mozilla Firefox
    "Google.Chrome"                   # Google Chrome
    "7zip.7zip"                       # 7-Zip
    "VideoLAN.VLC"                    # VLC Media Player
    "Adobe.Acrobat.Reader.64-bit"     # Adobe Acrobat Reader (64-bit)
    # Microsoft 365 / Office is intentionally excluded here.
    # Use Install-Office365Business.ps1 for proper ODT-based business deployment.
)
# =============================================================================

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output "--- $Message ---"
}

Write-Output "Program Installation Script"
Write-Output "Computer: $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

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
        Write-Output "  Winget requires Windows 10 1809+ with App Installer installed."
        Write-Output "  Install it from the Microsoft Store or via the App Installer package."
        exit 1
    }
} else {
    Write-Output "  winget found: $($winget.Source)"
}

Write-Step "Step 2: Validating program list"

$ActivePrograms = $Programs | Where-Object { $_ -and $_.Trim() -ne '' }

if ($ActivePrograms.Count -eq 0) {
    Write-Output "  No programs defined in the list. Edit the `$Programs array and re-run."
    exit 1
}

Write-Output "  $($ActivePrograms.Count) program(s) queued for installation:"
foreach ($pkg in $ActivePrograms) {
    Write-Output "    - $pkg"
}

Write-Step "Step 3: Installing programs"

foreach ($PackageId in $ActivePrograms) {
    Write-Output ""
    Write-Output "  Installing: $PackageId"

    $installed = winget list --id $PackageId --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0 -and ($installed -match $PackageId)) {
        Write-Output "  SKIPPED: $PackageId is already installed."
        continue
    }

    $result = winget install `
        --id $PackageId `
        --exact `
        --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity `
        2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Output "  SUCCESS: $PackageId installed."
    } elseif ($LASTEXITCODE -eq -1978335189) {
        Write-Output "  SKIPPED: $PackageId is already installed (winget code -1978335189)."
    } else {
        Write-Output "  FAILED: $PackageId â exit code $LASTEXITCODE"
        Write-Output "  winget output: $result"
        $script:Errors++
    }
}

Write-Output ""
if ($script:Errors -gt 0) {
    Write-Output "Completed with $($script:Errors) failure(s) on $env:COMPUTERNAME."
    Write-Output "Check output above for details on which packages failed."
    exit 1
} else {
    Write-Output "All installs completed successfully on $env:COMPUTERNAME."
    exit 0
}
