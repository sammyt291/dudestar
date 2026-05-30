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

    [string]$BuildRoot = (Join-Path $PSScriptRoot '.windows-build'),

    [switch]$SkipDeploy
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw 'This script must be run on Windows.'
}

$ProjectRoot = $PSScriptRoot
$MsysRoot = Join-Path $BuildRoot 'msys64'
$Bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
$MsysInstaller = Join-Path $BuildRoot 'msys2-base-x86_64-latest.sfx.exe'
$MsysUrl = 'https://github.com/msys2/msys2-installer/releases/download/nightly-x86_64/msys2-base-x86_64-latest.sfx.exe'

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Invoke-Native([string]$FilePath, [string[]]$Arguments) {
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE: $FilePath $($Arguments -join ' ')"
    }
}

function Invoke-Msys([string]$Command) {
    $env:MSYSTEM = 'UCRT64'
    $env:CHERE_INVOKING = '1'
    $env:DUDESTAR_PROJECT_ROOT = $ProjectRoot
    Invoke-Native $Bash @('-lc', "set -euo pipefail; $Command")
}

New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null

if (-not (Test-Path $Bash)) {
    Write-Step 'Downloading private MSYS2 bootstrap archive'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $MsysUrl -OutFile $MsysInstaller

    Write-Step 'Extracting MSYS2 into the project build directory'
    Invoke-Native $MsysInstaller @('-y', "-o$BuildRoot")

    if (-not (Test-Path $Bash)) {
        throw "MSYS2 extraction finished, but bash.exe was not found at $Bash"
    }
}

Write-Step 'Initializing MSYS2 package database'
Invoke-Msys 'pacman --noconfirm -Syuu || true'
Invoke-Msys 'pacman --noconfirm -Suu'

Write-Step 'Installing compiler and Qt build dependencies'
Invoke-Msys @'
pacman --noconfirm -S --needed \
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
qmake ../../dudestar.pro CONFIG+="$CONFIGURATION" CONFIG+=no_flite CONFIG+=no_static
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
windeployqt --"${CONFIGURATION}" --compiler-runtime package/dudestar.exe
'@

    Write-Host "`nBuild complete: $(Join-Path $ProjectRoot 'build\windows\package\dudestar.exe')" -ForegroundColor Green
} else {
    Write-Host "`nBuild complete: $(Join-Path $ProjectRoot "build\windows\$Configuration\dudestar.exe")" -ForegroundColor Green
}
