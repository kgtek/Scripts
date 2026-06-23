<#
.SYNOPSIS
    Completely removes all Microsoft Office versions from a Windows PC.

.DESCRIPTION
    Uses Microsoft's own SaRACmd (Support and Recovery Assistant) tool â
    the same engine Microsoft Support uses â to perform a deep removal of
    all Office versions including Microsoft 365, Office 2024, 2021, 2019,
    2016, 2013, 2010, and 2007, covering both Click-to-Run and MSI installs.

    Also removes the Microsoft Store (AppX) version of Office if present,
    and cleans up common leftover folders and registry keys afterward.

    Steps performed:
      1. Kill all running Office processes
      2. Download SaRACmd from Microsoft (requires internet)
      3. Run SaRACmd -OfficeVersion All for deep removal
      4. Remove Microsoft Store / AppX Office package if present
      5. Clean up leftover folders and registry keys
      6. Report results and recommend reboot

.NOTES
    SYNCRO SETUP:
      No script variables required. Run as SYSTEM (Syncro default).
      Internet access is required to download SaRACmd from Microsoft.
      A reboot after this script is strongly recommended.

    - SaRACmd is downloaded fresh from Microsoft each run to ensure
      the latest version is used. The ZIP is extracted to a temp folder
      and removed after use.
    - Exit code 0 = success, 1 = failure. Syncro flags based on exit code.
    - SaRACmd logs are written to %LOCALAPPDATA%\SaRALogs on the machine.
    - If the machine has no internet access, the script will fall back to
      a WMI/registry uninstall attempt and report what it found.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$script:Errors = 0
$SaRATempPath = "$env:TEMP\SaRACmd_Office"

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output "--- $Message ---"
}

Write-Output "Microsoft Office Complete Removal Script"
Write-Output "Computer: $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

Write-Step "Step 1: Stopping Office processes"

$OfficeProcesses = @(
    "WINWORD", "EXCEL", "POWERPNT", "OUTLOOK", "ONENOTE", "MSPUB",
    "MSACCESS", "LYNC", "Teams", "GROOVE", "INFOPATH", "VISIO",
    "WINPROJ", "msedge", "MSOUC", "OneDrive", "OfficeClickToRun",
    "AppVShNotify", "officec2rclient"
)

foreach ($proc in $OfficeProcesses) {
    $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($running) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Write-Output "  Stopped: $proc"
    }
}

Write-Step "Step 2: Downloading Microsoft SaRACmd removal tool"

$SaRACmdUrl = "https://aka.ms/SaRA_CommandLineVersionFiles"
$SaRAZip    = "$env:TEMP\SaRACmd.zip"
$SaRACmdExe = "$SaRATempPath\SaRAcmd.exe"
$SaRASuccess = $false

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $SaRACmdUrl -OutFile $SaRAZip -UseBasicParsing -ErrorAction Stop
    Write-Output "  Downloaded SaRACmd successfully."

    if (Test-Path $SaRATempPath) {
        Remove-Item -Path $SaRATempPath -Recurse -Force
    }
    Expand-Archive -Path $SaRAZip -DestinationPath $SaRATempPath -Force -ErrorAction Stop
    Remove-Item -Path $SaRAZip -Force -ErrorAction SilentlyContinue
    Write-Output "  Extracted SaRACmd to: $SaRATempPath"
}
catch {
    Write-Output "  WARNING: Could not download SaRACmd. Falling back to manual method."
    Write-Output "  Error: $($_.Exception.Message)"
    $script:Errors++
}

if (Test-Path $SaRACmdExe) {
    Write-Step "Step 3: Running SaRACmd - removing all Office versions"
    Write-Output "  This may take several minutes. Please wait..."

    $saraArgs = "-S OfficeScrubScenario -AcceptEula -OfficeVersion All -CloseOffice"
    $result = Start-Process -FilePath $SaRACmdExe `
                            -ArgumentList $saraArgs `
                            -Wait -PassThru -ErrorAction Stop

    switch ($result.ExitCode) {
        0  { Write-Output "  SaRACmd SUCCESS (exit 0): Office removal completed."; $SaRASuccess = $true }
        6  { Write-Output "  SaRACmd WARNING (exit 6): Office processes still running."; $script:Errors++ }
        10 { Write-Output "  SaRACmd ERROR (exit 10): Must run as administrator."; $script:Errors++ }
        default {
            Write-Output "  SaRACmd exit code: $($result.ExitCode). Check %LOCALAPPDATA%\SaRALogs for details."
            if ($result.ExitCode -ne 0) { $script:Errors++ }
        }
    }
    Remove-Item -Path $SaRATempPath -Recurse -Force -ErrorAction SilentlyContinue
}
else {
    Write-Step "Step 3 (Fallback): Attempting WMI uninstall of detected Office products"

    $OfficeProducts = Get-WmiObject -Class Win32_Product -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Microsoft Office|Microsoft 365" }

    if ($OfficeProducts) {
        foreach ($product in $OfficeProducts) {
            Write-Output "  Uninstalling: $($product.Name)"
            try {
                $product.Uninstall() | Out-Null
                Write-Output "  Uninstalled: $($product.Name)"
            } catch {
                Write-Output "  FAILED: $($product.Name) - $($_.Exception.Message)"
                $script:Errors++
            }
        }
    } else {
        Write-Output "  No Office products found via WMI."
    }

    $C2RUninstall = (Get-ItemProperty `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\O365*" `
        -ErrorAction SilentlyContinue).UninstallString

    if ($C2RUninstall) {
        Write-Output "  Found Click-to-Run uninstall string, running..."
        Start-Process -FilePath "cmd.exe" `
            -ArgumentList "/c $C2RUninstall /uninstall USERLICENSES=1 /quiet" `
            -Wait -ErrorAction SilentlyContinue
    }
}

Write-Step "Step 4: Removing Microsoft Store (AppX) Office package"

$AppXPackages = @(
    "Microsoft.Office.Desktop",
    "Microsoft.Office.Desktop.Access",
    "Microsoft.Office.Desktop.Excel",
    "Microsoft.Office.Desktop.Outlook",
    "Microsoft.Office.Desktop.PowerPoint",
    "Microsoft.Office.Desktop.Publisher",
    "Microsoft.Office.Desktop.Word",
    "Microsoft.MicrosoftOfficeHub"
)

foreach ($pkg in $AppXPackages) {
    $found = Get-AppxPackage -Name $pkg -AllUsers -ErrorAction SilentlyContinue
    if ($found) {
        try {
            Remove-AppxPackage -Package $found.PackageFullName -AllUsers -ErrorAction Stop
            Write-Output "  Removed AppX package: $pkg"
        } catch {
            Write-Output "  Could not remove AppX package: $pkg - $($_.Exception.Message)"
        }
    }
}

Write-Step "Step 5: Removing leftover folders and registry keys"

$LeftoverFolders = @(
    "$env:ProgramFiles\Microsoft Office",
    "${env:ProgramFiles(x86)}\Microsoft Office",
    "$env:ProgramFiles\Common Files\Microsoft Shared\ClickToRun",
    "${env:ProgramFiles(x86)}\Common Files\Microsoft Shared\ClickToRun",
    "$env:ProgramData\Microsoft\Office",
    "$env:ProgramData\Microsoft Help"
)

foreach ($folder in $LeftoverFolders) {
    if (Test-Path $folder) {
        try {
            & takeown.exe /F "$folder" /R /D Y 2>&1 | Out-Null
            & icacls.exe "$folder" /grant Administrators:F /T /Q 2>&1 | Out-Null
            Remove-Item -Path $folder -Recurse -Force -ErrorAction Stop
            Write-Output "  Removed: $folder"
        } catch {
            Write-Output "  Could not remove: $folder - $($_.Exception.Message)"
        }
    }
}

$LeftoverRegKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Office",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\O365HomePremRetail - en-us",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\O365ProPlusRetail - en-us"
)

foreach ($key in $LeftoverRegKeys) {
    if (Test-Path $key) {
        try {
            Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
            Write-Output "  Removed registry key: $key"
        } catch {
            Write-Output "  Could not remove registry key: $key"
        }
    }
}

Write-Output ""
if ($script:Errors -gt 0) {
    Write-Output "Completed with $($script:Errors) error(s) on $env:COMPUTERNAME."
    Write-Output "Check the output above and %LOCALAPPDATA%\SaRALogs for details."
    Write-Output "A reboot is recommended before any further troubleshooting."
    exit 1
} else {
    Write-Output "Office removal completed successfully on $env:COMPUTERNAME."
    Write-Output "Please REBOOT this machine to finish cleanup before reinstalling Office."
    exit 0
}
