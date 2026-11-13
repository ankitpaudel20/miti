# Install miti for the current user. No admin rights needed.
# Run from the extracted release folder:
#
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# It copies everything to %LOCALAPPDATA%\Programs\miti, puts that folder on your PATH,
# starts the tray app and makes it start at login. Undo with uninstall.ps1 (a copy is
# kept in the install folder).
#
# Written without access to Windows: never run.

$ErrorActionPreference = 'Stop'
$source = $PSScriptRoot
$dir = Join-Path $env:LOCALAPPDATA 'Programs\miti'

if (-not (Test-Path (Join-Path $source 'miti.exe'))) {
    throw 'miti.exe is not beside install.ps1. Run this from the extracted release folder.'
}

# A running copy would lock the files being replaced.
Get-Process MitiTray, miti -ErrorAction SilentlyContinue | Stop-Process -Force

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $dir -Recurse -Force -Exclude 'install.ps1', 'install.sh', 'uninstall.sh'
# Downloaded files carry a "from the internet" mark that makes Windows warn on every start.
Get-ChildItem $dir -Recurse -File | Unblock-File

# PATH for the current user. Read raw from the registry: the .NET call would expand
# entries like %USERPROFILE% and write them back flattened.
$env_key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$old = [string]$env_key.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
if (($old -split ';') -notcontains $dir) {
    $kind = if ($env_key.GetValueNames() -contains 'Path') { $env_key.GetValueKind('Path') } else { 'ExpandString' }
    $new = (@($old.TrimEnd(';'), $dir) | Where-Object { $_ }) -join ';'
    $env_key.SetValue('Path', $new, $kind)
    # A registry write alone is silent; setting any variable through .NET tells running programs to reload.
    [Environment]::SetEnvironmentVariable('MITI_PATH_REFRESH', $null, 'User')
}
$env_key.Close()

$tray = Join-Path $dir 'MitiTray.exe'
if (Test-Path $tray) {
    $link = Join-Path ([Environment]::GetFolderPath('Startup')) 'Nepali Date.lnk'
    $shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($link)
    $shortcut.TargetPath = $tray
    $shortcut.WorkingDirectory = $dir
    $shortcut.Save()

    $runtimes = & { try { dotnet --list-runtimes 2>$null } catch { } }
    if (-not ($runtimes -match 'Microsoft\.WindowsDesktop\.App (8|9|\d\d)\.')) {
        Write-Warning 'The tray app needs the .NET 8 Desktop Runtime or newer: https://dotnet.microsoft.com/download/dotnet/8.0'
    }
    Start-Process $tray
    Write-Host 'Tray app started. It will also start at every login.'
}

Write-Host "Installed to $dir"
Write-Host "Open a new terminal to use 'miti'. To remove: $dir\uninstall.ps1"
