<#
.SYNOPSIS
    Installs a predefined list of programs via winget with live progress
    display, then downloads and runs Office 365 Business from GitHub.

.DESCRIPTION
    Interactive version of Install-Programs.ps1 designed for local runs.
    Displays colored status output and progress bars. Not intended for
    Syncro â use Install-Programs.ps1 for unattended RMM deployment.

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
    @{ Id = "Mozilla.Firefox";             Name = "Mozilla Firefox"          }
    @{ Id = "Google.Chrome";               Name = "Google Chrome"            }
    @{ Id = "7zip.7zip";                   Name = "7-Zip"                    }
    @{ Id = "VideoLAN.VLC";               Name = "VLC Media Player"         }
    @{ Id = "Adobe.Acrobat.Reader.64-bit"; Name = "Adobe Acrobat Reader"     }
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
    Write-Host "  This streams from Microsoft CDN and may take 10-20 minutes." -ForegroundColor DarkYellow
    Write-Host ""

    Write-Progress -Activity "Program Installation" `
        -Status "Installing Microsoft 365 Business (streaming from CDN)..." `
        -PercentComplete 82 `
        -CurrentOperation "Running ODT â do not close this window"

    & $TempOfficeScript 2>&1 | ForEach-Object {
        Write-Host "         $_" -ForegroundColor DarkGray
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Status "SUCCESS" "Office 365 Business installed." "Green"
        $script:Success++
    } else {
        Write-Status "FAILED" "Office installer exited with code $LASTEXITCODE." "Red"
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
    Write-Host ""
    exit 1
} else {
    Write-Host "  All done! User must sign in to Microsoft 365 to activate Office." -ForegroundColor Green
    Write-Host ""
    exit 0
}
