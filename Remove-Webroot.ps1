<#
.SYNOPSIS
    Forcefully removes Webroot SecureAnywhere / OpenText Core Endpoint
    Protection and all remnants from a Windows PC.

.DESCRIPTION
    Runs in two phases designed to work around Webroot's self-protection:

      Phase 1 (first run): Attempts a clean uninstall via WRSA.exe, then
        stops and deletes all services, kills the process, purges registry
        keys, and removes all folders. A reboot is required after this run.

      Phase 2 (second run, post-reboot): Cleans up anything that survived
        phase 1 â services and folders that were locked during the first
        pass are typically accessible after reboot.

    Run this script twice with a reboot in between for a complete removal.

.NOTES
    SYNCRO SETUP:
      No script variables required. Run this script as SYSTEM â it needs
      to be elevated and Syncro's default execution context satisfies that.

    - If WRSA.exe is gone before you run this, that's fine â the script
      catches the error and moves on to the manual cleanup steps.
    - If Webroot is still present after two runs + reboot, the machine
      likely needs a Safe Mode boot to unlock the kernel driver (WRkrn).
      Webroot's own CleanWDF.exe tool (available from their support site)
      is the nuclear option for that scenario.
    - Exit code 0 = success (or already-clean), 1 = errors encountered.
      Syncro will flag failures based on exit code.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$script:Errors = 0

function Write-Step {
    param([string]$Message)
    Write-Output ""
    Write-Output "--- $Message ---"
}

function Remove-RegistryKey {
    param([string]$Path)
    if (Test-Path $Path) {
        try {
            Remove-Item -Path $Path -Force -Recurse -ErrorAction Stop
            Write-Output "  Removed: $Path"
        } catch {
            Write-Output "  FAILED to remove: $Path â $($_.Exception.Message)"
            $script:Errors++
        }
    }
}

function Remove-RegistryValue {
    param([string]$Path, [string]$Name)
    if (Test-Path $Path) {
        try {
            Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction Stop
            Write-Output "  Removed value: $Name from $Path"
        } catch {
            # Value may not exist â not an error worth flagging
        }
    }
}

function Remove-FolderForced {
    param([string]$Path)
    $expanded = [System.Environment]::ExpandEnvironmentVariables($Path)
    if (Test-Path $expanded) {
        try {
            & takeown.exe /F "$expanded" /R /D Y 2>&1 | Out-Null
            & icacls.exe "$expanded" /grant Administrators:F /T /Q 2>&1 | Out-Null
            Remove-Item -Path $expanded -Force -Recurse -ErrorAction Stop
            Write-Output "  Removed: $expanded"
        } catch {
            Write-Output "  FAILED to remove: $expanded â $($_.Exception.Message)"
            $script:Errors++
        }
    }
}

Write-Output "Webroot / OpenText Endpoint Removal Script"
Write-Output "Computer: $env:COMPUTERNAME  |  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Run this script TWICE with a reboot after the first run."

# STEP 1 â Attempt clean uninstall via WRSA.exe
Write-Step "Step 1: Attempting clean uninstall via WRSA.exe"

$WRSAPaths = @(
    "$env:ProgramFiles\Webroot\WRSA.exe",
    "${env:ProgramFiles(x86)}\Webroot\WRSA.exe"
)
foreach ($WRSAPath in $WRSAPaths) {
    if (Test-Path $WRSAPath) {
        Write-Output "  Found WRSA.exe at: $WRSAPath"
        try {
            Start-Process -FilePath $WRSAPath -ArgumentList "-uninstall" -Wait -ErrorAction Stop
            Write-Output "  WRSA.exe uninstall completed (exit may still require reboot)."
        } catch {
            Write-Output "  WRSA.exe uninstall failed or was blocked â continuing with manual removal."
        }
    }
}

# STEP 2 â Stop and delete Webroot services
Write-Step "Step 2: Stopping and deleting Webroot services"

$Services = @("WRSVC", "WRCoreService", "WRSkyClient", "WRkrn", "WRBoot", "WRCore", "wrUrlFlt")
foreach ($Svc in $Services) {
    $svcObj = Get-Service -Name $Svc -ErrorAction SilentlyContinue
    if ($svcObj) {
        Write-Output "  Stopping service: $Svc"
        & sc.exe stop $Svc 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        & sc.exe delete $Svc 2>&1 | Out-Null
        Write-Output "  Deleted service: $Svc"
    }
}

# STEP 3 â Kill Webroot processes
Write-Step "Step 3: Killing Webroot processes"

$Processes = @("WRSA", "WRSkyClient")
foreach ($Proc in $Processes) {
    $running = Get-Process -Name $Proc -ErrorAction SilentlyContinue
    if ($running) {
        Stop-Process -Name $Proc -Force -ErrorAction SilentlyContinue
        Write-Output "  Killed process: $Proc"
    }
}

# STEP 4 â Remove registry keys
Write-Step "Step 4: Removing registry keys"

$RegKeys = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\WRUNINST",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WRUNINST",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\WRUNINST",
    "HKLM:\SOFTWARE\WOW6432Node\WRData",
    "HKLM:\SOFTWARE\WOW6432Node\WRCore",
    "HKLM:\SOFTWARE\WOW6432Node\WRMIDDdata",
    "HKLM:\SOFTWARE\WOW6432Node\webroot",
    "HKLM:\SOFTWARE\WRData",
    "HKLM:\SOFTWARE\WRMIDData",
    "HKLM:\SOFTWARE\WRCore",
    "HKLM:\SOFTWARE\webroot",
    "HKLM:\SYSTEM\ControlSet001\services\WRSVC",
    "HKLM:\SYSTEM\ControlSet001\services\WRkrn",
    "HKLM:\SYSTEM\ControlSet001\services\WRBoot",
    "HKLM:\SYSTEM\ControlSet001\services\WRCore",
    "HKLM:\SYSTEM\ControlSet001\services\WRCoreService",
    "HKLM:\SYSTEM\ControlSet001\services\WRSkyClient",
    "HKLM:\SYSTEM\ControlSet001\services\wrUrlFlt",
    "HKLM:\SYSTEM\ControlSet002\services\WRSVC",
    "HKLM:\SYSTEM\ControlSet002\services\WRkrn",
    "HKLM:\SYSTEM\ControlSet002\services\WRBoot",
    "HKLM:\SYSTEM\ControlSet002\services\WRCore",
    "HKLM:\SYSTEM\ControlSet002\services\WRCoreService",
    "HKLM:\SYSTEM\ControlSet002\services\WRSkyClient",
    "HKLM:\SYSTEM\ControlSet002\services\wrUrlFlt",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRSVC",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRkrn",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRBoot",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRCore",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRCoreService",
    "HKLM:\SYSTEM\CurrentControlSet\services\WRSkyClient",
    "HKLM:\SYSTEM\CurrentControlSet\services\wrUrlFlt"
)

foreach ($Key in $RegKeys) {
    Remove-RegistryKey -Path $Key
}

# STEP 5 â Remove startup registry values
Write-Step "Step 5: Removing startup registry entries"

$StartupPaths = @(
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
)
foreach ($StartupPath in $StartupPaths) {
    Remove-RegistryValue -Path $StartupPath -Name "WRSVC"
    Remove-RegistryValue -Path $StartupPath -Name "WRSkyClient"
}

# STEP 6 â Remove folders
Write-Step "Step 6: Removing Webroot folders"

$Folders = @(
    "%ProgramData%\WRData",
    "%ProgramData%\WRCore",
    "%ProgramData%\WRMIDDdata",
    "%ProgramFiles%\Webroot",
    "%ProgramFiles(x86)%\Webroot",
    "%ProgramData%\Microsoft\Windows\Start Menu\Programs\Webroot SecureAnywhere",
    "%TEMP%\WRSA",
    "%SystemRoot%\System32\drivers\WRkrn.sys",
    "%SystemRoot%\System32\drivers\wrsvc.sys"
)

foreach ($Folder in $Folders) {
    Remove-FolderForced -Path $Folder
}

Write-Output ""
if ($script:Errors -gt 0) {
    Write-Output "Completed with $($script:Errors) error(s). A reboot + second run"
    Write-Output "should clear any locked files. See output above for details."
    exit 1
} else {
    Write-Output "Completed with no errors on $env:COMPUTERNAME."
    Write-Output "If this was the FIRST run: reboot, then run this script again."
    Write-Output "If this was the SECOND run: Webroot removal is complete."
    exit 0
}
