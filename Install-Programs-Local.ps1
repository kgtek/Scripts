<#
.SYNOPSIS
    Installs a predefined list of programs via winget with live progress
    display, then downloads and runs Office 365 Business from GitHub with
    real-time ODT log streaming so you can watch the install progress.

.DESCRIPTION
    Interactive version of Install-Programs.ps1 designed for local runs.
    Displays colored status output and progress bars. Office 365 runs the
    ODT in the background while a separate thread tails the ODT log and
    streams updates to the console in real time.

.NOTES
    Run from an elevated PowerShell prompt on the local machine.
    Internet access required.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = 'SilentlyContinue'
$script:Errors   = 0
$script:Skipped  = 0
$script:Success  = 0

# =============================================================================
$Programs = @(
    @{ Id = "Mozilla.Firefox";             Name = "Mozilla Firefox"      }
    @{ Id = "Google.Chrome";               Name = "Google Chrome"        }
    @{ Id = "7zip.7zip";                   Name = "7-Zip"                }
    @{ Id = "VideoLAN.VLC";               Name = "VLC Media Player"     }
    @{ Id = "Adobe.Acrobat.Reader.64-bit"; Name = "Adobe Acrobat Reader" }
)
$Office365ScriptUrl = "https://raw.githubusercontent.com/kgtek/Scripts/main/Install-Office365Business.ps1"
# =============================================================================

function Write-Header {
    param([string]$Text)
    $width = 63
    $pad   = [math]::Max(0, ($width - $Text.Length - 2) / 2)
    $line  = "â" * $width
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host ("â" + " " * [math]::Floor($pad) + $Text + " " * [math]::Ceiling($pad) + "â") -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

function Write-Status {
    param([string]$Tag, [string]$Message, [string]$Color = "White")
    $tagFormatted = $Tag.PadRight(9)
    Write-Host "  [$tagFormatted] " -ForegroundColor DarkGray -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

function Write-SectionHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host "  âââ $Message âââ" -ForegroundColor DarkCyan
    Write-Host ""
}

Write-Header "Program Installation"
Write-Host "  Computer : " -ForegroundColor DarkGray -NoNewline
Write-Host $env:COMPUTERNAME -ForegroundColor White
Write-Host "  Started  : " -ForegroundColor DarkGray -NoNewline
Write-Host (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
Write-Host "  Programs : " -ForegroundColor DarkGray -NoNewline
Write-Host "$($Programs.Count) via winget + Office 365 via GitHub" -ForegroundColor White

Write-SectionHeader "Step 1 of 3 â Checking winget"
Write-Progress -Activity "Program Installation" -Status "Checking winget..." -PercentComplete 2

$winget = Get-Command winget -ErrorAction SilentlyContinue
if (-not $winget) {
    $wingetPath = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" `
        -ErrorAction SilentlyContinue | Select-Object -Last 1 -ExpandProperty Path
    if ($wingetPath) {
        Set-Alias winget $wingetPath -Scope Script
        Write-Status "FOUND" "winget at: $wingetPath" "Green"
    } else {
        Write-Status "FAILED" "winget not found â requires Windows 10 1809+ with App Installer." "Red"
        Write-Progress -Activity "Program Installation" -Completed
        exit 1
    }
} else {
    Write-Status "FOUND" "winget available" "Green"
}

Write-SectionHeader "Step 2 of 3 â Installing Programs via Winget"

$total   = $Programs.Count
$current = 0

foreach ($pkg in $Programs) {
    $current++
    $pct = [math]::Round(($current / ($total + 1)) * 75)

    Write-Progress -Activity "Program Installation" `
        -Status "[$current/$total] Installing $($pkg.Name)..." `
        -PercentComplete $pct `
        -CurrentOperation "Running winget install $($pkg.Id)"

    Write-Host "  " -NoNewline
    Write-Host "[$current/$total]" -ForegroundColor DarkGray -NoNewline
    Write-Host " $($pkg.Name)" -ForegroundColor White -NoNewline

    $installed = winget list --id $pkg.Id --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0 -and ($installed -match $pkg.Id)) {
        Write-Host " â " -ForegroundColor DarkGray -NoNewline
        Write-Host "Already installed, skipping." -ForegroundColor DarkYellow
        $script:Skipped++
        continue
    }

    Write-Host ""

    winget install `
        --id $pkg.Id --exact --silent `
        --accept-package-agreements `
        --accept-source-agreements `
        --disable-interactivity 2>&1 | ForEach-Object {
            Write-Host "         $_" -ForegroundColor DarkGray
        }

    if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq -1978335189) {
        Write-Status "SUCCESS" "$($pkg.Name) installed." "Green"
        $script:Success++
    } else {
        Write-Status "FAILED" "$($pkg.Name) â exit code $LASTEXITCODE" "Red"
        $script:Errors++
    }
}

Write-SectionHeader "Step 3 of 3 â Office 365 Business (via GitHub)"

Write-Progress -Activity "Program Installation" `
    -Status "Downloading Office 365 Business installer from GitHub..." `
    -PercentComplete 78 `
    -CurrentOperation $Office365ScriptUrl

Write-Host "  Downloading installer script..." -ForegroundColor DarkGray

$TempOfficeScript = "$env:TEMP\Install-Office365Business.ps1"
$ODTLogPath       = "$env:TEMP\ODTLogs"

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $Office365ScriptUrl -OutFile $TempOfficeScript -UseBasicParsing -ErrorAction Stop
    Write-Status "DOWNLOADED" "Script pulled from GitHub successfully." "Green"
} catch {
    Write-Status "FAILED" "Could not download Office script â $($_.Exception.Message)" "Red"
    $script:Errors++
}

if (Test-Path $TempOfficeScript) {
    Write-Host ""
    Write-Host "  Installing Microsoft 365 Business..." -ForegroundColor White
    Write-Host "  Streaming output from ODT log in real time." -ForegroundColor DarkYellow
    Write-Host "  This may take 10-20 minutes â do not close this window." -ForegroundColor DarkYellow
    Write-Host ""

    Write-Progress -Activity "Program Installation" `
        -Status "Installing Microsoft 365 Business (streaming from CDN)..." `
        -PercentComplete 82 `
        -CurrentOperation "ODT running â check log output below"

    New-Item -Path $ODTLogPath -ItemType Directory -Force | Out-Null

    $job = Start-Job -ScriptBlock {
        param($Script)
        & powershell.exe -ExecutionPolicy Bypass -NonInteractive -File $Script
        return $LASTEXITCODE
    } -ArgumentList $TempOfficeScript

    Write-Host "  ODT started (Job ID: $($job.Id)). Streaming log..." -ForegroundColor DarkGray
    Write-Host ""

    $lastLogFile   = $null
    $lastPos       = 0
    $dotTimer      = 0
    $installedFlag = $false

    while ($job.State -eq 'Running') {
        Start-Sleep -Milliseconds 500
        $dotTimer++

        $logFile = Get-ChildItem -Path $ODTLogPath -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1

        if ($logFile) {
            if ($logFile.FullName -ne $lastLogFile) {
                $lastLogFile = $logFile.FullName
                $lastPos     = 0
                Write-Host "  [LOG] $($logFile.Name)" -ForegroundColor DarkGray
            }

            try {
                $stream = [System.IO.File]::Open($logFile.FullName,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::ReadWrite)
                $stream.Seek($lastPos, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader  = New-Object System.IO.StreamReader($stream)
                $newText = $reader.ReadToEnd()
                $lastPos = $stream.Position
                $reader.Close()
                $stream.Close()

                if ($newText) {
                    $newText -split "`n" | ForEach-Object {
                        $line = $_.Trim()
                        if ($line) {
                            if ($line -match "Error|Failed|FAILED") {
                                Write-Host "  [LOG] $line" -ForegroundColor Red
                            } elseif ($line -match "Success|Complete|Successful") {
                                Write-Host "  [LOG] $line" -ForegroundColor Green
                                $installedFlag = $true
                            } elseif ($line -match "Download|Installing|Configur") {
                                Write-Host "  [LOG] $line" -ForegroundColor Cyan
                            } else {
                                Write-Host "  [LOG] $line" -ForegroundColor DarkGray
                            }
                        }
                    }
                }
            } catch {
                # Log file locked briefly â just skip this cycle
            }
        } else {
            if ($dotTimer % 10 -eq 0) {
                Write-Host "  Waiting for ODT to start..." -ForegroundColor DarkGray
            }
        }
    }

    $jobOutput = Receive-Job -Job $job
    $exitCode  = $job.ChildJobs[0].Output | Select-Object -Last 1
    Remove-Job -Job $job -Force

    Write-Host ""

    $logFile = Get-ChildItem -Path $ODTLogPath -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if ($logFile) {
        try {
            $stream = [System.IO.File]::Open($logFile.FullName,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite)
            $stream.Seek($lastPos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $reader  = New-Object System.IO.StreamReader($stream)
            $newText = $reader.ReadToEnd()
            $reader.Close()
            $stream.Close()
            if ($newText) {
                $newText -split "`n" | ForEach-Object {
                    $line = $_.Trim()
                    if ($line) {
                        if ($line -match "Error|Failed|FAILED") {
                            Write-Host "  [LOG] $line" -ForegroundColor Red
                        } elseif ($line -match "Success|Complete|Successful") {
                            Write-Host "  [LOG] $line" -ForegroundColor Green
                        } else {
                            Write-Host "  [LOG] $line" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        } catch {}
    }

    $officeInstalled = Get-ItemProperty `
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" `
        -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match "Microsoft 365|Microsoft Office" } |
        Select-Object -First 1

    if ($officeInstalled) {
        Write-Status "SUCCESS" "Office 365 Business installed: $($officeInstalled.DisplayName)" "Green"
        $script:Success++
    } elseif ($installedFlag) {
        Write-Status "SUCCESS" "ODT reported success (registry entry may take a moment to appear)." "Green"
        $script:Success++
    } else {
        Write-Status "FAILED" "Office does not appear to be installed. Check $ODTLogPath for details." "Red"
        $script:Errors++
    }

    Remove-Item -Path $TempOfficeScript -Force -ErrorAction SilentlyContinue
}

Write-Progress -Activity "Program Installation" -Completed

Write-Header "Installation Complete"

Write-Host "  Installed  : " -ForegroundColor DarkGray -NoNewline
Write-Host $script:Success -ForegroundColor Green

Write-Host "  Skipped    : " -ForegroundColor DarkGray -NoNewline
Write-Host $script:Skipped -ForegroundColor DarkYellow

Write-Host "  Failed     : " -ForegroundColor DarkGray -NoNewline
if ($script:Errors -gt 0) {
    Write-Host $script:Errors -ForegroundColor Red
} else {
    Write-Host $script:Errors -ForegroundColor Green
}

Write-Host "  Finished   : " -ForegroundColor DarkGray -NoNewline
Write-Host (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -ForegroundColor White
Write-Host ""

if ($script:Errors -gt 0) {
    Write-Host "  One or more installations failed. Review output above." -ForegroundColor Red
    Write-Host "  ODT logs saved at: $ODTLogPath" -ForegroundColor DarkGray
    Write-Host ""
    exit 1
} else {
    Write-Host "  All done! User must sign in to Microsoft 365 to activate Office." -ForegroundColor Green
    Write-Host ""
    exit 0
}
