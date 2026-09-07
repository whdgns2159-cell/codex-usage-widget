param()

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$script:BaseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$xamlPath = Join-Path $script:BaseDir "CodexUsageWidget.xaml"
$xamlText = [System.IO.File]::ReadAllText($xamlPath, [System.Text.Encoding]::UTF8)
$xmlReader = New-Object System.Xml.XmlNodeReader ([xml]$xamlText)
$script:Window = [Windows.Markup.XamlReader]::Load($xmlReader)

$names = @(
    "StatusText", "LiveDot", "PlanText", "FiveRemainingText", "FiveUsedText",
    "FiveResetText", "FiveProgress", "WeekRemainingText", "WeekUsedText",
    "WeekResetText", "WeekProgress", "LifetimeText", "AlwaysOnTopCheck", "RefreshButton"
)
foreach ($name in $names) {
    Set-Variable -Name $name -Value $script:Window.FindName($name) -Scope Script
}

$script:ServerProcess = $null
$script:StdoutTask = $null
$script:StderrTask = $null
$script:LastErrorLine = ""
$script:NextRequestId = 1
$script:Pending = @{}
$script:IsInitialized = $false
$script:FiveResetUnix = $null
$script:WeekResetUnix = $null
$script:LastRefreshRequest = [DateTime]::MinValue
$script:SecondsSinceRefresh = 0

function Get-UiString([string]$Key) {
    return [string]$script:Window.FindResource($Key)
}

function Format-UiString([string]$Key, [object[]]$Values) {
    return [string]::Format((Get-UiString $Key), $Values)
}

function Set-ConnectionState([bool]$Connected, [string]$Message) {
    $script:StatusText.Text = $Message
    if ($Connected) {
        $script:LiveDot.Fill = [Windows.Media.Brushes]::MediumSpringGreen
    } else {
        $script:LiveDot.Fill = [Windows.Media.Brushes]::Orange
    }
}

function Find-CodexCommand {
    $native = Get-Command "codex.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $native) {
        return [pscustomobject]@{ Mode = "native"; Path = $native.Source }
    }

    $root = Join-Path $env:USERPROFILE ".codex\bin\wsl"
    $binary = Get-ChildItem -LiteralPath $root -Filter "codex" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $binary) {
        throw "Codex CLI binary was not found under the Codex installation directory."
    }

    $fullPath = $binary.FullName
    $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
    $rest = $fullPath.Substring(2).Replace("\", "/")
    $profilePath = $env:USERPROFILE
    $profileDrive = $profilePath.Substring(0, 1).ToLowerInvariant()
    $profileRest = $profilePath.Substring(2).Replace("\", "/")
    $codexHome = "/mnt/$profileDrive$profileRest/.codex"
    return [pscustomobject]@{ Mode = "wsl"; Path = "/mnt/$drive$rest"; CodexHome = $codexHome }
}

function Send-ServerMessage([hashtable]$Message) {
    if ($null -eq $script:ServerProcess -or $script:ServerProcess.HasExited) {
        throw "Codex app-server is not running."
    }
    $json = $Message | ConvertTo-Json -Compress -Depth 12
    $script:ServerProcess.StandardInput.WriteLine($json)
    $script:ServerProcess.StandardInput.Flush()
}

function Send-Request([string]$Method, [hashtable]$Params, [string]$Kind) {
    $id = $script:NextRequestId
    $script:NextRequestId += 1
    $script:Pending[$id] = $Kind
    Send-ServerMessage @{ id = $id; method = $Method; params = $Params }
    return $id
}

function Request-Usage {
    if (-not $script:IsInitialized) { return }
    $alreadyPending = $script:Pending.Values -contains "limits"
    if (-not $alreadyPending) {
        [void](Send-Request "account/rateLimits/read" @{} "limits")
    }
    $usagePending = $script:Pending.Values -contains "usage"
    if (-not $usagePending) {
        [void](Send-Request "account/usage/read" @{} "usage")
    }
    $accountPending = $script:Pending.Values -contains "account"
    if (-not $accountPending) {
        [void](Send-Request "account/read" @{ refreshToken = $false } "account")
    }
    $script:LastRefreshRequest = [DateTime]::Now
}

function Get-ClampedPercent($Value) {
    if ($null -eq $Value) { return 0 }
    return [Math]::Max(0, [Math]::Min(100, [int]$Value))
}

function Get-ProgressBrush([int]$Percent) {
    if ($Percent -ge 90) { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(239, 68, 68)) }
    if ($Percent -ge 70) { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(245, 158, 11)) }
    return New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(124, 92, 252))
}

function Format-ResetTime($UnixSeconds) {
    if ($null -eq $UnixSeconds) { return Get-UiString "ResetUnknown" }
    $epoch = [DateTime]::SpecifyKind([DateTime]"1970-01-01 00:00:00", [DateTimeKind]::Utc)
    $localTime = $epoch.AddSeconds([double]$UnixSeconds).ToLocalTime()
    return Format-UiString "ResetFormat" @($localTime.ToString("M/d HH:mm"))
}

function Update-LimitCard($Window, $UsedText, $RemainingText, $ResetText, $Progress, [string]$Which) {
    if ($null -eq $Window) { return }
    $percent = Get-ClampedPercent $Window.usedPercent
    $UsedText.Text = Format-UiString "UsedFormat" @($percent)
    $RemainingText.Text = Format-UiString "RemainingFormat" @(100 - $percent)
    $ResetText.Text = Format-ResetTime $Window.resetsAt
    $Progress.Value = $percent
    $Progress.Foreground = Get-ProgressBrush $percent
    if ($Which -eq "five") { $script:FiveResetUnix = $Window.resetsAt }
    if ($Which -eq "week") { $script:WeekResetUnix = $Window.resetsAt }
}

function Apply-RateLimits($Result) {
    $bucket = $null
    if ($null -ne $Result.rateLimitsByLimitId) {
        $codexProperty = $Result.rateLimitsByLimitId.PSObject.Properties |
            Where-Object { $_.Name -eq "codex" } |
            Select-Object -First 1
        if ($null -ne $codexProperty) { $bucket = $codexProperty.Value }
    }
    if ($null -eq $bucket) { $bucket = $Result.rateLimits }
    if ($null -eq $bucket) { throw "No Codex rate-limit bucket was returned." }

    $fiveWindow = $null
    $weekWindow = $null
    foreach ($candidate in @($bucket.primary, $bucket.secondary)) {
        if ($null -eq $candidate) { continue }
        if ([int64]$candidate.windowDurationMins -eq 300) { $fiveWindow = $candidate }
        elseif ([int64]$candidate.windowDurationMins -eq 10080) { $weekWindow = $candidate }
    }
    if ($null -eq $fiveWindow) { $fiveWindow = $bucket.primary }
    if ($null -eq $weekWindow) { $weekWindow = $bucket.secondary }

    Update-LimitCard $fiveWindow $script:FiveUsedText $script:FiveRemainingText $script:FiveResetText $script:FiveProgress "five"
    Update-LimitCard $weekWindow $script:WeekUsedText $script:WeekRemainingText $script:WeekResetText $script:WeekProgress "week"

    if ($null -ne $bucket.planType) {
        $script:PlanText.Text = ([string]$bucket.planType).ToUpperInvariant()
    } else {
        $script:PlanText.Text = "CODEX"
    }
    $timeText = [DateTime]::Now.ToString("HH:mm:ss")
    Set-ConnectionState $true (Format-UiString "StatusUpdated" @($timeText))
}

function Apply-TokenUsage($Result) {
    if ($null -ne $Result.summary -and $null -ne $Result.summary.lifetimeTokens) {
        $formatted = ([int64]$Result.summary.lifetimeTokens).ToString("N0")
        $script:LifetimeText.Text = Format-UiString "LifetimeFormat" @($formatted)
    }
}

function Handle-ServerLine([string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) { return }
    try {
        $message = $Line | ConvertFrom-Json
    } catch {
        return
    }

    if ($null -ne $message.id) {
        $id = [int]$message.id
        if (-not $script:Pending.ContainsKey($id)) { return }
        $kind = $script:Pending[$id]
        $script:Pending.Remove($id)

        if ($null -ne $message.error) {
            $errorMessage = [string]$message.error.message
            Set-ConnectionState $false (Format-UiString "StatusError" @($errorMessage))
            return
        }

        if ($kind -eq "initialize") {
            $script:IsInitialized = $true
            Send-ServerMessage @{ method = "initialized"; params = @{} }
            Request-Usage
        } elseif ($kind -eq "limits") {
            Apply-RateLimits $message.result
        } elseif ($kind -eq "usage") {
            Apply-TokenUsage $message.result
        } elseif ($kind -eq "account") {
            if ($null -eq $message.result.account -and $message.result.requiresOpenaiAuth) {
                Set-ConnectionState $false (Get-UiString "StatusNoLogin")
                $script:PlanText.Text = "OFFLINE"
            }
        }
        return
    }

    if ($message.method -eq "account/rateLimits/updated") {
        Request-Usage
    }
}

function Stop-CodexServer {
    if ($null -ne $script:ServerProcess) {
        try {
            if (-not $script:ServerProcess.HasExited) {
                $script:ServerProcess.StandardInput.Close()
                $script:ServerProcess.Kill()
            }
        } catch {}
        try { $script:ServerProcess.Dispose() } catch {}
    }
    $script:ServerProcess = $null
    $script:StdoutTask = $null
    $script:StderrTask = $null
    $script:IsInitialized = $false
    $script:Pending = @{}
}

function Start-CodexServer {
    Stop-CodexServer
    Set-ConnectionState $false (Get-UiString "StatusLoading")
    $script:PlanText.Text = "..."
    try {
        $codexCommand = Find-CodexCommand
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($codexCommand.Mode -eq "native") {
            $psi.FileName = $codexCommand.Path
            $psi.Arguments = "app-server --stdio"
        } else {
        $homePsi = New-Object System.Diagnostics.ProcessStartInfo
        $homePsi.FileName = Join-Path $env:SystemRoot "System32\wsl.exe"
        $homePsi.Arguments = "--exec /usr/bin/printenv HOME"
        $homePsi.UseShellExecute = $false
        $homePsi.CreateNoWindow = $true
        $homePsi.RedirectStandardOutput = $true
        $homeProcess = [System.Diagnostics.Process]::Start($homePsi)
        $wslHome = $homeProcess.StandardOutput.ReadToEnd().Trim()
        $homeProcess.WaitForExit()
        $homeProcess.Dispose()
        if ([string]::IsNullOrWhiteSpace($wslHome) -or -not $wslHome.StartsWith("/")) {
            throw "The WSL home directory could not be determined."
        }

        $psi.FileName = Join-Path $env:SystemRoot "System32\wsl.exe"
        $sqliteHome = "$wslHome/.codex/sqlite"
        $psi.Arguments = "--exec /usr/bin/env `"CODEX_HOME=$($codexCommand.CodexHome)`" `"CODEX_SQLITE_HOME=$sqliteHome`" `"$($codexCommand.Path)`" app-server --stdio"
        }
        $psi.UseShellExecute = $false
        if ($codexCommand.Mode -eq "native") {
            $psi.EnvironmentVariables["CODEX_HOME"] = Join-Path $env:USERPROFILE ".codex"
        }
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        $script:ServerProcess = New-Object System.Diagnostics.Process
        $script:ServerProcess.StartInfo = $psi
        if (-not $script:ServerProcess.Start()) { throw "Codex app-server could not be started." }
        $script:StdoutTask = $script:ServerProcess.StandardOutput.ReadLineAsync()
        $script:StderrTask = $script:ServerProcess.StandardError.ReadLineAsync()

        $initId = $script:NextRequestId
        $script:NextRequestId += 1
        $script:Pending[$initId] = "initialize"
        Send-ServerMessage @{
            id = $initId
            method = "initialize"
            params = @{
                clientInfo = @{ name = "codex-usage-widget"; title = "Codex Usage Widget"; version = "1.0.1" }
                capabilities = @{ experimentalApi = $true }
            }
        }
    } catch {
        Stop-CodexServer
        Set-ConnectionState $false (Format-UiString "StatusError" @($_.Exception.Message))
    }
}

$script:IoTimer = New-Object Windows.Threading.DispatcherTimer
$script:IoTimer.Interval = [TimeSpan]::FromMilliseconds(100)
$script:IoTimer.Add_Tick({
    try {
        if ($null -ne $script:StdoutTask -and $script:StdoutTask.IsCompleted) {
            $line = $script:StdoutTask.Result
            if ($null -ne $line) {
                Handle-ServerLine $line
                $script:StdoutTask = $script:ServerProcess.StandardOutput.ReadLineAsync()
            }
        }
        if ($null -ne $script:StderrTask -and $script:StderrTask.IsCompleted) {
            $errorLine = $script:StderrTask.Result
            if ($null -ne $errorLine) {
                $script:LastErrorLine = $errorLine
                $script:StderrTask = $script:ServerProcess.StandardError.ReadLineAsync()
            }
        }
        if ($null -ne $script:ServerProcess -and $script:ServerProcess.HasExited -and $script:IsInitialized) {
            $script:IsInitialized = $false
            Set-ConnectionState $false (Format-UiString "StatusError" @("Codex app-server stopped"))
        }
    } catch {
        Set-ConnectionState $false (Format-UiString "StatusError" @($_.Exception.Message))
    }
})

$script:RefreshTimer = New-Object Windows.Threading.DispatcherTimer
$script:RefreshTimer.Interval = [TimeSpan]::FromSeconds(1)
$script:RefreshTimer.Add_Tick({
    $script:SecondsSinceRefresh += 1
    if ($script:SecondsSinceRefresh -ge 60) {
        $script:SecondsSinceRefresh = 0
        try { Request-Usage } catch {}
    }
})

$script:RefreshButton.Add_Click({
    try {
        $script:SecondsSinceRefresh = 0
        if ($null -eq $script:ServerProcess -or $script:ServerProcess.HasExited) {
            Start-CodexServer
        } else {
            Request-Usage
        }
    } catch {
        Set-ConnectionState $false (Format-UiString "StatusError" @($_.Exception.Message))
    }
})

$script:AlwaysOnTopCheck.Add_Checked({ $script:Window.Topmost = $true })
$script:AlwaysOnTopCheck.Add_Unchecked({ $script:Window.Topmost = $false })
$script:Window.Add_Closed({
    $script:IoTimer.Stop()
    $script:RefreshTimer.Stop()
    Stop-CodexServer
})

$script:IoTimer.Start()
$script:RefreshTimer.Start()
Start-CodexServer
[void]$script:Window.ShowDialog()
