param(
    [switch]$Quiet,
    [string]$Version = "1.0.1"
)

$ErrorActionPreference = "Stop"
$productName = "Codex Usage Widget"
$installDir = Join-Path $env:LOCALAPPDATA "Programs\CodexUsageWidget"
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$desktopDir = [Environment]::GetFolderPath("Desktop")

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
$payloadFiles = @(
    "CodexUsageWidget.ps1",
    "CodexUsageWidget.xaml",
    "Start-CodexUsageWidget.vbs",
    "Uninstall.ps1",
    "Uninstall-CodexUsageWidget.vbs",
    "README.md",
    "LICENSE"
)
foreach ($file in $payloadFiles) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $installDir $file) -Force
}

$shell = New-Object -ComObject WScript.Shell
$launcherPath = Join-Path $installDir "Start-CodexUsageWidget.vbs"
$shortcutTargets = @(
    (Join-Path $startMenuDir "$productName.lnk"),
    (Join-Path $desktopDir "$productName.lnk")
)
foreach ($shortcutPath in $shortcutTargets) {
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = Join-Path $env:SystemRoot "System32\wscript.exe"
    $shortcut.Arguments = '"' + $launcherPath + '"'
    $shortcut.WorkingDirectory = $installDir
    $shortcut.IconLocation = (Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe") + ",0"
    $shortcut.Description = "View Codex 5-hour and weekly usage"
    $shortcut.Save()
}

$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexUsageWidget"
New-Item -Path $uninstallKey -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "DisplayName" -Value $productName -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "DisplayVersion" -Value $Version -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "Publisher" -Value "Codex Usage Widget contributors" -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "InstallLocation" -Value $installDir -PropertyType String -Force | Out-Null
$uninstallCommand = 'wscript.exe "' + (Join-Path $installDir "Uninstall-CodexUsageWidget.vbs") + '"'
New-ItemProperty -Path $uninstallKey -Name "UninstallString" -Value $uninstallCommand -PropertyType String -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "NoModify" -Value 1 -PropertyType DWord -Force | Out-Null
New-ItemProperty -Path $uninstallKey -Name "NoRepair" -Value 1 -PropertyType DWord -Force | Out-Null

if (-not $Quiet) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show(
        "Installation completed. A shortcut was added to the Desktop and Start menu.",
        $productName,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}
