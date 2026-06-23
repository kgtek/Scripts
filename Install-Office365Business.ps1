<#
.SYNOPSIS
    Silently deploys Microsoft 365 Apps for Business (O365BusinessRetail)
    using the Office Deployment Tool (ODT).

.DESCRIPTION
    Downloads the latest Office Deployment Tool from Microsoft, generates
    a configuration XML targeting the O365BusinessRetail SKU, and runs a
    fully silent installation. Cleans up all temp files after completion.

    This is the correct deployment method for Microsoft 365 Business Basic,
    Business Standard, and Business Premium licensed users. The user will
    still need to sign in with their Microsoft 365 account to activate
    after installation â that is a Microsoft licensing requirement and
    cannot be bypassed by any deployment script.

.NOTES
    SYNCRO SETUP:
      No script variables required. Run as SYSTEM (Syncro default).
      Internet access required â ODT streams Office from Microsoft CDN.
      This install can take 10-20 minutes depending on connection speed.
      Syncro's default script timeout may need to be increased.

    CUSTOMIZATION:
      Edit the CONFIG BLOCK below to adjust:
        $Channel    â update channel (MonthlyEnterprise recommended for
                      business; more predictable than Current channel)
        $Arch       â 64 or 32 (64-bit strongly recommended)
        $Language   â IETF language tag (en-us default)
        $ExcludeApps â comma-separated list of apps to exclude from install

    - Exit code 0 = success, 1 = failure. Syncro flags based on exit code.
    - ODT install logs written to %TEMP%\ODTLogs on the target machine.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Stop'

# =============================================================================
# CONFIG BLOCK â Edit these values to customize the deployment
# =============================================================================
$Channel      = "MonthlyEnterprise"   # MonthlyEnterprise | Current | SemiAnnual
$Arch         = "64"                  # 64 | 32
$Language     = "en-us"              # IETF language tag
$ExcludeApps  = @("Lync", "Groove")  # Apps to exclude (Teams installs separately)
# =============================================================================

$ODTTemp      = "$env:TEMP\ODTDeploy"
$ODTZip       = "$ODTTemp\ODT.exe"
$ODTSetup     = "$ODTTemp\setup.exe"
$ConfigXML    = "$ODTTemp\O365Business.xml"
$ODTLogPath   = "$env:TEMP\ODTLogs"
$ODTUrl       = "https://aka.ms/ODT"

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output "--- $Message ---"
}

Write-Output "Microsoft 365 Business Deployment Script (ODT)"
Write-Output "Computer: $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "SKU: O365BusinessRetail  |  Channel: $Channel  |  Arch: $Arch-bit"

Write-Step "Step 1: Checking for existing Office installation"

$ExistingOffice = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
    -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "Microsoft 365|Microsoft Office" } |
    Select-Object -First 1

if ($ExistingOffice) {
    Write-Output "  Office already installed: $($ExistingOffice.DisplayName)"
    Write-Output "  Skipping installation. Remove existing Office first if a reinstall is needed."
    exit 0
}

Write-Output "  No existing Office installation found. Proceeding."

Write-Step "Step 2: Preparing temp directory"

if (Test-Path $ODTTemp) {
    Remove-Item -Path $ODTTemp -Recurse -Force
}
New-Item -Path $ODTTemp -ItemType Directory -Force | Out-Null
New-Item -Path $ODTLogPath -ItemType Directory -Force | Out-Null
Write-Output "  Temp path: $ODTTemp"

Write-Step "Step 3: Downloading Office Deployment Tool from Microsoft"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $ODTUrl -OutFile $ODTZip -UseBasicParsing -ErrorAction Stop
    Write-Output "  Downloaded ODT successfully."
} catch {
    Write-Output "  FAILED: Could not download ODT â $($_.Exception.Message)"
    exit 1
}

Write-Step "Step 4: Extracting ODT"

try {
    $extractResult = Start-Process -FilePath $ODTZip `
        -ArgumentList "/quiet /extract:`"$ODTTemp`"" `
        -Wait -PassThru -ErrorAction Stop

    if (-not (Test-Path $ODTSetup)) {
        Write-Output "  FAILED: setup.exe not found after extraction."
        exit 1
    }
    Write-Output "  ODT extracted successfully."
} catch {
    Write-Output "  FAILED: ODT extraction error â $($_.Exception.Message)"
    exit 1
}

Write-Step "Step 5: Generating configuration XML"

$ExcludeXML = ""
foreach ($app in $ExcludeApps) {
    $ExcludeXML += "      <ExcludeApp ID=`"$app`" />`n"
}

$ConfigContent = @"
<Configuration>
  <Add OfficeClientEdition="$Arch" Channel="$Channel">
    <Product ID="O365BusinessRetail">
      <Language ID="$Language" />
$ExcludeXML    </Product>
  </Add>
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Property Name="SharedComputerLicensing" Value="0" />
  <Display Level="None" AcceptEULA="TRUE" />
  <Logging Level="Standard" Path="$ODTLogPath" />
  <Updates Enabled="TRUE" Channel="$Channel" />
</Configuration>
"@

$ConfigContent | Out-File -FilePath $ConfigXML -Encoding UTF8 -Force
Write-Output "  Config XML written to: $ConfigXML"
Write-Output "  Preview:"
Get-Content $ConfigXML | ForEach-Object { Write-Output "    $_" }

Write-Step "Step 6: Installing Microsoft 365 Business (this may take 10-20 minutes)"
Write-Output "  Streaming Office from Microsoft CDN â do not interrupt..."

try {
    $installResult = Start-Process -FilePath $ODTSetup `
        -ArgumentList "/configure `"$ConfigXML`"" `
        -Wait -PassThru -ErrorAction Stop

    if ($installResult.ExitCode -eq 0) {
        Write-Output "  SUCCESS: Office 365 Business installed (exit code 0)."
    } else {
        Write-Output "  FAILED: ODT exit code $($installResult.ExitCode)."
        Write-Output "  Check ODT logs at: $ODTLogPath"
        Write-Output "  Common codes: 17002=incomplete, 17004=invalid config, 30088=download error"
        exit 1
    }
} catch {
    Write-Output "  FAILED: Installation error â $($_.Exception.Message)"
    exit 1
}

Write-Step "Step 7: Cleaning up temp files"

Remove-Item -Path $ODTTemp -Recurse -Force -ErrorAction SilentlyContinue
Write-Output "  Temp files removed."

Write-Output ""
Write-Output "âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ"
Write-Output "Microsoft 365 Business installation complete on $env:COMPUTERNAME."
Write-Output "The user must sign in with their Microsoft 365 account to activate."
Write-Output "ODT logs available at: $ODTLogPath"
Write-Output "âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ"
exit 0
