param([string]$Version = "1.0.1")

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$appDir = Join-Path $repoRoot "app"
$distDir = Join-Path $repoRoot "dist"
$stageDir = Join-Path $env:WINDIR ("Temp\CodexUsageWidgetBuild-" + $PID)
$payloadDir = Join-Path $stageDir "payload"
$setupPath = Join-Path $stageDir "CodexUsageWidget-Setup.exe"
$sedPath = Join-Path $stageDir "CodexUsageWidget.sed"

if (Test-Path $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $distDir -Force | Out-Null

Copy-Item -LiteralPath (Join-Path $appDir "CodexUsageWidget.ps1") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $appDir "CodexUsageWidget.xaml") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $appDir "Start-CodexUsageWidget.vbs") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Uninstall.ps1") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Uninstall-CodexUsageWidget.vbs") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $repoRoot "README.md") -Destination $payloadDir
Copy-Item -LiteralPath (Join-Path $repoRoot "LICENSE") -Destination $payloadDir

$installCmd = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File `"%~dp0Install.ps1`" -Version `"$Version`" %*`r`n"
[System.IO.File]::WriteAllText((Join-Path $payloadDir "install.cmd"), $installCmd, [System.Text.Encoding]::ASCII)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot "Install.ps1") -Destination $payloadDir

$sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=1
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$setupPath
FriendlyName=Codex Usage Widget Setup $Version
AppLaunched=install.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=install.cmd -Quiet
UserQuietInstCmd=install.cmd -Quiet
SourceFiles=SourceFiles
[SourceFiles]
SourceFiles0=$payloadDir\
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
%FILE3%=
%FILE4%=
%FILE5%=
%FILE6%=
%FILE7%=
%FILE8%=
[Strings]
FILE0=install.cmd
FILE1=Install.ps1
FILE2=CodexUsageWidget.ps1
FILE3=CodexUsageWidget.xaml
FILE4=Start-CodexUsageWidget.vbs
FILE5=Uninstall.ps1
FILE6=Uninstall-CodexUsageWidget.vbs
FILE7=README.md
FILE8=LICENSE
"@
[System.IO.File]::WriteAllText($sedPath, $sed, [System.Text.Encoding]::ASCII)

$iexpress = Join-Path $env:SystemRoot "System32\iexpress.exe"
$process = Start-Process -FilePath $iexpress -ArgumentList "/N", "/Q", $sedPath -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path $setupPath)) {
    throw "IExpress failed with exit code $($process.ExitCode)."
}

$finalSetup = Join-Path $distDir "CodexUsageWidget-Setup-$Version.exe"
Copy-Item -LiteralPath $setupPath -Destination $finalSetup -Force

$portableStage = Join-Path $stageDir "portable"
New-Item -ItemType Directory -Path $portableStage -Force | Out-Null
Copy-Item -Path (Join-Path $appDir "*") -Destination $portableStage -Recurse
$portableZip = Join-Path $distDir "CodexUsageWidget-Portable-$Version.zip"
Compress-Archive -Path (Join-Path $portableStage "*") -DestinationPath $portableZip -Force

try { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction Stop } catch { }
Write-Output $finalSetup
Write-Output $portableZip
