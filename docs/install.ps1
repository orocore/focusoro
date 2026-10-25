# Focusoro installer for Windows (PowerShell).
#
#   irm https://focusoro.com/install.ps1 | iex
#
# Downloads focusoro.exe from the GitHub release, checks its SHA-256,
# installs it in %LOCALAPPDATA%\Programs\Focusoro, adds that folder to the
# user's PATH (no administrator rights needed) and creates a Start menu
# shortcut. Afterwards, open a new terminal and type: focusoro
#
# Options (environment variables, set before running):
#   $env:FOCUSORO_VERSION = "1.1.0"   install that version instead of the latest
# Uninstall:
#   & ([scriptblock]::Create((irm https://focusoro.com/install.ps1))) -Uninstall

param([switch]$Uninstall)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'  # Invoke-WebRequest is much faster without it

$Repo = 'orocore/focusoro'
$Asset = 'focusoro-windows-x86_64.exe'
$InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Focusoro'
$Exe = Join-Path $InstallDir 'focusoro.exe'
$Shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Focusoro.lnk'

function Get-UserPath {
  [Environment]::GetEnvironmentVariable('Path', 'User')
}

if ($Uninstall) {
  Remove-Item -Force -ErrorAction SilentlyContinue $Exe, $Shortcut
  $parts = (Get-UserPath) -split ';' | Where-Object { $_ -and $_ -ne $InstallDir }
  [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'User')
  Write-Host 'Focusoro was removed.'
  Write-Host "Your data was kept. To delete it too, remove: $(Join-Path $env:APPDATA 'focusoro')"
  return
}

$Version = $env:FOCUSORO_VERSION
if ($env:FOCUSORO_DOWNLOAD_BASE) {
  $Base = $env:FOCUSORO_DOWNLOAD_BASE  # pruebas: otra fuente
} elseif ($Version) {
  $Base = "https://github.com/$Repo/releases/download/v$($Version.TrimStart('v'))"
} else {
  $Base = "https://github.com/$Repo/releases/latest/download"
}

$Tmp = Join-Path ([IO.Path]::GetTempPath()) ("focusoro-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Tmp | Out-Null
try {
  Write-Host 'Downloading Focusoro...'
  # TLS 1.2 for Windows PowerShell 5.1 on older systems.
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/$Asset" -OutFile (Join-Path $Tmp $Asset)
  Invoke-WebRequest -UseBasicParsing -Uri "$Base/sha256sums.txt" -OutFile (Join-Path $Tmp 'sha256sums.txt')

  $line = Get-Content (Join-Path $Tmp 'sha256sums.txt') | Where-Object { $_ -match "\s\*?$([regex]::Escape($Asset))$" }
  if (-not $line) { throw "No checksum for $Asset in this release." }
  $expected = ($line -split '\s+')[0].ToLower()
  $actual = (Get-FileHash -Algorithm SHA256 (Join-Path $Tmp $Asset)).Hash.ToLower()
  if ($expected -ne $actual) { throw 'The download is corrupted (checksum mismatch). Please try again.' }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Move-Item -Force (Join-Path $Tmp $Asset) $Exe
} finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Tmp
}

# PATH (user, no admin): new terminals find `focusoro`.
$userPath = Get-UserPath
if (-not (($userPath -split ';') -contains $InstallDir)) {
  $newPath = if ($userPath) { "$userPath;$InstallDir" } else { $InstallDir }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
}
$env:Path = "$env:Path;$InstallDir"

# Start menu shortcut: opens in Windows Terminal when it's installed.
try {
  $shell = New-Object -ComObject WScript.Shell
  $link = $shell.CreateShortcut($Shortcut)
  $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
  if ($wt) {
    $link.TargetPath = $wt.Source
    $link.Arguments = "`"$Exe`""
  } else {
    $link.TargetPath = $Exe
  }
  $link.WorkingDirectory = $env:USERPROFILE
  $link.IconLocation = "$Exe,0"
  $link.Description = 'Pomodoro sessions, focus tracking and goals'
  $link.Save()
} catch {
  # best-effort: el atajo es un extra
}

$installed = & $Exe --version
Write-Host ''
Write-Host "OK  $installed installed in $InstallDir" -ForegroundColor Green
Write-Host ''
Write-Host 'Open a new terminal and type:'
Write-Host ''
Write-Host '    focusoro' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Or open "Focusoro" from the Start menu. Press h inside the app for every shortcut.'
