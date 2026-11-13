# Remove everything miti puts on this machine, for the current user.
# Needs nothing but this file, and is safe to run twice:
#
#   powershell -ExecutionPolicy Bypass -File uninstall.ps1
#
# It removes: running miti programs, the login shortcut, the PATH entry, the tray icon
# settings Windows remembers, and the folder %LOCALAPPDATA%\Programs\miti.
#
# Written without access to Windows: never run.

$ErrorActionPreference = 'Continue'
$dir = Join-Path $env:LOCALAPPDATA 'Programs\miti'

Get-Process MitiTray, miti -ErrorAction SilentlyContinue | Stop-Process -Force

$link = Join-Path ([Environment]::GetFolderPath('Startup')) 'Nepali Date.lnk'
if (Test-Path $link) { Remove-Item $link -Force; Write-Host "removed $link" }

# PATH: read and write raw, so other entries keep their %VARIABLES%.
$env_key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$old = [string]$env_key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$new = @($old -split ';' | Where-Object { $_ -and $_.TrimEnd('\') -ne $dir }) -join ';'
if ($new -ne $old.TrimEnd(';')) {
    $env_key.SetValue('Path', $new, $env_key.GetValueKind('Path'))
    [Environment]::SetEnvironmentVariable('MITI_PATH_REFRESH', $null, 'User') # makes running programs reload PATH
    Write-Host 'removed miti from PATH'
}
$env_key.Close()

# Windows 11 keeps a settings entry per tray icon it has ever shown.
$icons = 'HKCU:\Control Panel\NotifyIconSettings'
if (Test-Path $icons) {
    Get-ChildItem $icons | Where-Object {
        (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).ExecutablePath -like '*\MitiTray.exe'
    } | ForEach-Object { Remove-Item $_.PSPath -Recurse -Force; Write-Host 'removed tray icon settings' }
}

# This script may be running from inside the folder it deletes; step out first.
Set-Location $env:TEMP
if (Test-Path $dir) { Remove-Item $dir -Recurse -Force; Write-Host "removed $dir" }

Write-Host 'miti is uninstalled.'
