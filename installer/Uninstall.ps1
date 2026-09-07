param([switch]$Quiet)

$ErrorActionPreference = "SilentlyContinue"
$productName = "Codex Usage Widget"
$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$startMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$productName.lnk"
$desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$productName.lnk"

Get-CimInstance Win32_Process |
    Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like "*$installDir\CodexUsageWidget.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force }

Remove-Item -LiteralPath $startMenuShortcut -Force
Remove-Item -LiteralPath $desktopShortcut -Force
Remove-Item -LiteralPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexUsageWidget" -Recurse -Force

if (-not $Quiet) {
    Add-Type -AssemblyName PresentationFramework
    [void][System.Windows.MessageBox]::Show(
        "Codex Usage Widget was removed.",
        $productName,
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Information
    )
}

$cleanupPath = Join-Path $env:TEMP ("CodexUsageWidget-Uninstall-" + [guid]::NewGuid().ToString("N") + ".cmd")
$quotedInstallDir = $installDir.Replace('"', '""')
$cleanup = "@echo off`r`nping 127.0.0.1 -n 2 > nul`r`nrmdir /s /q `"$quotedInstallDir`"`r`ndel /q `"%~f0`"`r`n"
[System.IO.File]::WriteAllText($cleanupPath, $cleanup, [System.Text.Encoding]::ASCII)
Start-Process -FilePath (Join-Path $env:SystemRoot "System32\cmd.exe") -ArgumentList "/c `"$cleanupPath`"" -WindowStyle Hidden
