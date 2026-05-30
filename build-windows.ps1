<#
.SYNOPSIS
Bootstraps a private MSYS2/Qt toolchain and builds DUDE-Star for Windows.

Run from an extracted source zip on Windows with:
  .\build-windows.cmd

No system-wide compiler, Qt install, Git checkout, or administrator rights are required.
The first run downloads MSYS2 and Qt packages into .windows-build; later runs reuse them.
#>
[CmdletBinding()]
param(
    [ValidateSet('release', 'debug')]
    [string]$Configuration = 'release',

    [string]$BuildRoot = '',

    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptRoot = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif (-not [string]::IsNullOrWhiteSpace($MyInvocation.MyCommand.Path)) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
} else {
    (Get-Location).ProviderPath
}

$ProjectRoot = (Resolve-Path -LiteralPath $ScriptRoot).ProviderPath
if ([string]::IsNullOrWhiteSpace($BuildRoot)) {
    $BuildRoot = Join-Path $ProjectRoot '.windows-build'
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw 'This script must be run on Windows.'
}

$MsysRoot = Join-Path $BuildRoot 'msys64'
$Bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$Pacman = Join-Path $MsysRoot 'usr\bin\pacman.exe'
$MsysInstaller = Join-Path $BuildRoot 'msys2-base-x86_64-latest.sfx.exe'
$MsysUrl = 'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-Msys([string]$Command) {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    $env:DUDESTAR_PROJECT_ROOT = $ProjectRoot

    # PowerShell 5's native command-line quoting can corrupt multi-line
    # `bash -lc` command strings that contain nested quotes and command
    # substitutions (for example, `$(nproc)`). Write the command to a
    # temporary script and execute that script directly so bash receives the
    # content exactly as authored.
    $MsysTmp = Join-Path $MsysRoot 'tmp'
    New-Item -ItemType Directory -Force -Path $MsysTmp | Out-Null

    $ScriptName = "msys-command-{0}.sh" -f ([Guid]::NewGuid().ToString('N'))
    $ScriptPath = Join-Path $MsysTmp $ScriptName
    $ScriptText = "set -euo pipefail`nexport PATH=/ucrt64/bin:/usr/bin:`${PATH:-}`n$Command"
    $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ScriptPath, $ScriptText, $Utf8NoBom)

    try {
        Invoke-Native $Bash @('-e', '-u', '-o', 'pipefail', "/tmp/$ScriptName")
    } finally {
        Remove-Item -LiteralPath $ScriptPath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MsysWithRetry([string]$Description, [string]$Command, [int]$Attempts = 3) {
    for ($Attempt = 1; $Attempt -le $Attempts; $Attempt++) {
        try {
            Invoke-Msys $Command
            return
        } catch {
            if ($Attempt -ge $Attempts) {
                throw
            }

            $DelaySeconds = 10 * $Attempt
            Write-Warning "$Description failed on attempt $Attempt of $Attempts. Retrying in $DelaySeconds seconds. $($_.Exception.Message)"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

function Install-Msys2([switch]$ForceDownload) {
    Write-Step 'Downloading private MSYS2 bootstrap archive'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if ($ForceDownload -and (Test-Path $MsysInstaller)) {
        Remove-Item -LiteralPath $MsysInstaller -Force
    }
    if ($ForceDownload -or -not (Test-Path $MsysInstaller)) {
        Invoke-WebRequest -UseBasicParsing -Uri $MsysUrl -OutFile $MsysInstaller
    } else {
        Write-Host "Reusing cached MSYS2 bootstrap archive at $MsysInstaller"
    }

    Write-Step 'Extracting MSYS2 into the project build directory'
    Invoke-Native $MsysInstaller @('-y', "-o$BuildRoot")

    if (-not (Test-Path $Bash)) {
        throw "MSYS2 extraction finished, but bash.exe was not found at $Bash"
    }
    if (-not (Test-Path $Pacman)) {
        throw "MSYS2 extraction finished, but pacman.exe was not found at $Pacman"
    }
}

if (-not (Test-Path $Bash) -or -not (Test-Path $Pacman)) {
    if ((Test-Path $Bash) -and -not (Test-Path $Pacman)) {
        Write-Warning "Existing MSYS2 bootstrap is incomplete: bash.exe exists but pacman.exe is missing at $Pacman. Recreating $MsysRoot."
        Remove-Item -LiteralPath $MsysRoot -Recurse -Force
        Install-Msys2 -ForceDownload
    } else {
        Install-Msys2
    }
}

Write-Step 'Initializing MSYS2 package database'
Invoke-MsysWithRetry 'MSYS2 package database synchronization' 'pacman --noconfirm --disable-download-timeout -Syuu || true'
Invoke-MsysWithRetry 'MSYS2 system upgrade' 'pacman --noconfirm --disable-download-timeout -Suu'

Write-Step 'Installing compiler and Qt build dependencies'
Invoke-MsysWithRetry 'MSYS2 dependency installation' @'
pacman --noconfirm --disable-download-timeout -S --needed \
  base-devel \
  mingw-w64-ucrt-x86_64-gcc \
  mingw-w64-ucrt-x86_64-make \
  mingw-w64-ucrt-x86_64-qt5-base \
  mingw-w64-ucrt-x86_64-qt5-tools \
  mingw-w64-ucrt-x86_64-qt5-multimedia \
  mingw-w64-ucrt-x86_64-qt5-serialport
'@

Write-Step "Building DUDE-Star ($Configuration)"
$env:DUDESTAR_BUILD_CONFIGURATION = $Configuration
Invoke-Msys @'
export PATH=/ucrt64/bin:/usr/bin:$PATH
export CONFIGURATION="$DUDESTAR_BUILD_CONFIGURATION"
cd "$(cygpath -u "$DUDESTAR_PROJECT_ROOT")"
rm -rf build/windows
mkdir -p build/windows
cd build/windows
QMAKE="$(command -v qmake-qt5 || command -v qmake)"
echo "Using qmake: $QMAKE"
"$QMAKE" ../../dudestar.pro CONFIG+="$CONFIGURATION" CONFIG+=no_flite CONFIG+=no_static
mingw32-make -j"$(nproc)"
'@

if (-not $SkipDeploy) {
    Write-Step 'Copying runtime DLLs next to dudestar.exe'
    Invoke-Msys @'
export PATH=/ucrt64/bin:/usr/bin:$PATH
export CONFIGURATION="$DUDESTAR_BUILD_CONFIGURATION"
cd "$(cygpath -u "$DUDESTAR_PROJECT_ROOT")/build/windows"
mkdir -p package
cp "${CONFIGURATION}/dudestar.exe" package/
WINDEPLOYQT="$(command -v windeployqt-qt5 || command -v windeployqt)"
echo "Using windeployqt: $WINDEPLOYQT"
"$WINDEPLOYQT" --"${CONFIGURATION}" --compiler-runtime package/dudestar.exe
'@

    Write-Host "`nBuild complete: $(Join-Path $ProjectRoot 'build\windows\package\dudestar.exe')" -ForegroundColor Green
} else {
    Write-Host "`nBuild complete: $(Join-Path $ProjectRoot "build\windows\$Configuration\dudestar.exe")" -ForegroundColor Green
}
