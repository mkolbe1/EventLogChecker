# Event Log Checker - Enhanced Edition
# Version: 1.0.0
# GitHub: https://github.com/mkolbe1/EventLogChecker
$script:Version = "1.0.3"
$script:GitHubRawUrl = "https://raw.githubusercontent.com/mkolbe1/EventLogChecker/main/EventLogChecker.ps1"


# Self-relaunch with bypass if constrained
if ($ExecutionContext.SessionState.LanguageMode -eq 'ConstrainedLanguage') {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# Config path
$script:ConfigPath = Join-Path $PSScriptRoot "EventLogChecker.config.json"

# Default config
$script:Config = @{
    SaveReport   = $false
    ReportPath   = [Environment]::GetFolderPath("Desktop")
    MaxEvents    = 0
    ShowVerbose  = $true
}


function Get-LatestCommitMessage {
    try {
        $apiUrl = "https://api.github.com/repos/mkolbe1/EventLogChecker/commits/main"
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add("User-Agent", "EventLogChecker")
        $json = $webClient.DownloadString($apiUrl)
        if ($json -match '"message"\s*:\s*"([^"\\n]+)') {
            return $matches[1].Trim()
        }
    } catch { }
    return "No patch notes available"
}

function Check-ForUpdates {
    try {
        Write-Host "  >> " -ForegroundColor DarkCyan -NoNewline
        Write-Host "Checking for updates" -ForegroundColor Gray -NoNewline

        $webClient = New-Object System.Net.WebClient
        $remoteContent = $webClient.DownloadString($script:GitHubRawUrl)

        $remoteVersion = $null
        foreach ($line in ($remoteContent -split "`n")) {
            if ($line -match '^\$script:Version\s*=\s*"([^"]+)"') {
                $remoteVersion = $matches[1]
                break
            }
        }

        if ($null -eq $remoteVersion) {
            Write-Host ".............. Could not read remote version" -ForegroundColor DarkGray
            return
        }

        $current = [Version]$script:Version
        $remote  = [Version]$remoteVersion

        if ($remote -gt $current) {
            Write-Host ".............. Update available!" -ForegroundColor Green
            Write-Host ""

            $patchNotes = Get-LatestCommitMessage
            $verPad     = $script:Version.PadRight(38)
            $remPad     = $remoteVersion.PadRight(38)
            $notePad    = if ($patchNotes.Length -gt 38) { $patchNotes.Substring(0,35) + "..." } else { $patchNotes.PadRight(38) }

            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Yellow
            Write-Host "  |  UPDATE AVAILABLE                                            |" -ForegroundColor Yellow
            Write-Host "  |  Current version : $verPad|" -ForegroundColor Yellow
            Write-Host "  |  New version     : $remPad|" -ForegroundColor Yellow
            Write-Host "  |  Patch notes     : $notePad|" -ForegroundColor Yellow
            Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Would you like to update now? [Y/N]: " -ForegroundColor White -NoNewline
            $answer = (Read-Host).Trim().ToUpper()

            if ($answer -eq "Y") {
                Write-Host ""
                Write-Host "  Downloading update..." -ForegroundColor Yellow
                $scriptPath = $PSCommandPath
                $tempPath   = "$scriptPath.tmp"
                $bytes = [System.Text.Encoding]::UTF8.GetPreamble() + [System.Text.Encoding]::UTF8.GetBytes($remoteContent)
                [System.IO.File]::WriteAllBytes($tempPath, $bytes)
                Write-Host "  Applying update and relaunching..." -ForegroundColor Yellow
                $cmd = "Start-Sleep 2; Copy-Item '$tempPath' '$scriptPath' -Force; Remove-Item '$tempPath' -Force; Start-Process powershell.exe -ArgumentList '-ExecutionPolicy Bypass -File `"$scriptPath`"'"
                Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -Command $cmd"
                exit
            } else {
                Write-Host "  Skipping update. Restart anytime to be prompted again." -ForegroundColor DarkGray
            }
        } else {
            Write-Host ".............. Up to date (v$($script:Version))" -ForegroundColor Green
        }
    } catch {
        Write-Host ".............. Could not reach GitHub (offline?)" -ForegroundColor DarkGray
    }
}

function Load-Config {
    if (Test-Path $script:ConfigPath) {
        try {
            $loaded = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            foreach ($key in @("SaveReport","ReportPath","MaxEvents","ShowVerbose")) {
                if ($null -ne $loaded.$key) { $script:Config[$key] = $loaded.$key }
            }
        } catch { }
    }
}

function Save-Config {
    try {
        $script:Config | ConvertTo-Json | Set-Content $script:ConfigPath -Encoding UTF8
    } catch {
        Write-Host "  [!] Could not save config: $_" -ForegroundColor Red
    }
}

function Show-BootVerbose {
    Clear-Host
    Write-Host ""
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |           STARTUP DIAGNOSTICS AND INFO                       |" -ForegroundColor DarkGray
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""

    $psVer     = $PSVersionTable.PSVersion.ToString()
    $policy    = (Get-ExecutionPolicy -Scope Process).ToString()
    $isAdmin   = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
    $adminVal  = if ($isAdmin) { "Running as Administrator  [OK]" } else { "Standard User -- some logs may be restricted" }
    $configVal = if (Test-Path $script:ConfigPath) { "Config found" } else { "No config found -- using defaults" }
    $evtSvc    = (Get-Service -Name EventLog -ErrorAction SilentlyContinue)
    $evtVal    = if ($evtSvc -and $evtSvc.Status -eq "Running") { "Windows Event Log -- RUNNING [OK]" } else { "Event Log service status unknown" }

    $bootSteps = @(
        @{ msg = "Checking PowerShell version";         val = "PS $psVer" }
        @{ msg = "Checking execution policy";           val = "Scope=Process: $policy" }
        @{ msg = "Verifying bypass is active";          val = "ExecutionPolicy Bypass -- ACTIVE" }
        @{ msg = "Checking administrator privileges";   val = $adminVal }
        @{ msg = "Locating config file";                val = $configVal }
        @{ msg = "Loading configuration";               val = "Done" }
        @{ msg = "Checking Event Log service";          val = $evtVal }
        @{ msg = "Initializing UI engine";              val = "ASCII renderer ready" }
        @{ msg = "All systems go";                      val = "" }
    )

    foreach ($step in $bootSteps) {
        Start-Sleep -Milliseconds 170
        Write-Host "  >> " -ForegroundColor DarkCyan -NoNewline
        Write-Host $step.msg -ForegroundColor Gray -NoNewline
        if ($step.val) {
            $dots = "." * ([math]::Max(2, 50 - $step.msg.Length))
            Write-Host $dots -ForegroundColor DarkGray -NoNewline
            Write-Host " $($step.val)" -ForegroundColor Green
        } else {
            Write-Host ""
        }
    }

    Write-Host ""
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Execution Policy Note:" -ForegroundColor Yellow
    Write-Host "    This script auto-relaunches with ExecutionPolicy Bypass." -ForegroundColor Gray
    Write-Host "    You can also run it manually with:" -ForegroundColor Gray
    Write-Host "    powershell.exe -ExecutionPolicy Bypass -File EventLogChecker.ps1" -ForegroundColor Cyan
    Write-Host "    Or right-click the script and choose 'Run with PowerShell'." -ForegroundColor Gray
    Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Press any key to enter the main menu..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Show-Title {
    Clear-Host
    Write-Host ""
    Write-Host "  ███████╗██╗   ██╗███████╗███╗   ██╗████████╗    ██╗      ██████╗  ██████╗ " -ForegroundColor Cyan
    Write-Host "  ██╔════╝██║   ██║██╔════╝████╗  ██║╚══██╔══╝    ██║     ██╔═══██╗██╔════╝ " -ForegroundColor Cyan
    Write-Host "  █████╗  ██║   ██║█████╗  ██╔██╗ ██║   ██║       ██║     ██║   ██║██║  ███╗" -ForegroundColor Cyan
    Write-Host "  ██╔══╝  ╚██╗ ██╔╝██╔══╝  ██║╚██╗██║   ██║       ██║     ██║   ██║██║   ██║" -ForegroundColor Cyan
    Write-Host "  ███████╗ ╚████╔╝ ███████╗██║ ╚████║   ██║       ███████╗╚██████╔╝╚██████╔╝" -ForegroundColor Cyan
    Write-Host "  ╚══════╝  ╚═══╝  ╚══════╝╚═╝  ╚═══╝   ╚═╝       ╚══════╝ ╚═════╝  ╚═════╝ " -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   ██████╗██╗  ██╗███████╗ ██████╗██╗  ██╗███████╗██████╗ " -ForegroundColor Yellow
    Write-Host "  ██╔════╝██║  ██║██╔════╝██╔════╝██║ ██╔╝██╔════╝██╔══██╗" -ForegroundColor Yellow
    Write-Host "  ██║     ███████║█████╗  ██║     █████╔╝ █████╗  ██████╔╝" -ForegroundColor Yellow
    Write-Host "  ██║     ██╔══██║██╔══╝  ██║     ██╔═██╗ ██╔══╝  ██╔══██╗" -ForegroundColor Yellow
    Write-Host "  ╚██████╗██║  ██║███████╗╚██████╗██║  ██╗███████╗██║  ██║" -ForegroundColor Yellow
    Write-Host "   ╚═════╝╚═╝  ╚═╝╚══════╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |       Windows System Event Log Analysis Tool  v2.0          |" -ForegroundColor DarkCyan
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
}

function Show-Menu {
    Write-Host "  +----------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |             MAIN  MENU                 |" -ForegroundColor White
    Write-Host "  +----------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |  [S]  Start Scan                       |" -ForegroundColor DarkGray
    Write-Host "  |  [A]  About                            |" -ForegroundColor DarkGray
    Write-Host "  |  [X]  Settings                         |" -ForegroundColor DarkGray
    Write-Host "  |  [Q]  Quit                             |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Choice: " -ForegroundColor White -NoNewline
}

function Show-Loading {
    $frames = @("|", "/", "-", "\\")
    $steps = @(
        "Connecting to Event Log service   ",
        "Querying System log entries       ",
        "Categorizing events by level      ",
        "Computing statistics              ",
        "Rendering report                  "
    )
    foreach ($step in $steps) {
        for ($i = 0; $i -lt 10; $i++) {
            $f = $frames[$i % $frames.Count]
            Write-Host "`r  [$f]  $step" -ForegroundColor Yellow -NoNewline
            Start-Sleep -Milliseconds 60
        }
    }
    Write-Host "`r  [OK] Scan complete!                                     " -ForegroundColor Green
    Start-Sleep -Milliseconds 300
}

function Get-SystemEvents {
    try {
        if ($script:Config.MaxEvents -gt 0) {
            return Get-WinEvent -LogName 'System' -MaxEvents $script:Config.MaxEvents -ErrorAction Stop
        } else {
            return Get-WinEvent -LogName 'System' -ErrorAction Stop
        }
    } catch {
        try {
            if ($script:Config.MaxEvents -gt 0) {
                return Get-EventLog -LogName System -Newest $script:Config.MaxEvents -ErrorAction Stop
            } else {
                return Get-EventLog -LogName System -ErrorAction Stop
            }
        } catch {
            return $null
        }
    }
}

function Build-ReportText {
    param($stats, $totalCount, $oldest, $newest)
    $lines = @()
    $lines += ("=" * 66)
    $lines += "  EVENT LOG CHECKER -- SYSTEM LOG REPORT"
    $lines += "  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += ("=" * 66)
    $lines += ""
    $lines += "  Log Range    : $oldest  to  $newest"
    $lines += "  Total Events : $totalCount"
    $lines += ""
    $lines += ("  {0,-18} {1,10}   {2,8}   {3}" -f "Category", "Count", "Percent", "Bar")
    $lines += "  " + ("-" * 62)
    $maxVal = ($stats.Values | Measure-Object -Maximum).Maximum
    foreach ($entry in ($stats.GetEnumerator() | Sort-Object Value -Descending)) {
        $pct = [math]::Round(($entry.Value / $totalCount) * 100, 1)
        $bar = "#" * [math]::Round(($entry.Value / $maxVal) * 24)
        $lines += ("  {0,-18} {1,10}   {2,7}%   {3}" -f $entry.Key, $entry.Value, $pct, $bar)
    }
    $lines += ""
    $lines += ("  {0,-18} {1,10}   {2,7}%" -f "TOTAL", $totalCount, "100.0")
    $lines += ("=" * 66)
    return ($lines -join "`r`n")
}

function Save-Report {
    param([string]$reportText)
    try {
        if (-not (Test-Path $script:Config.ReportPath)) {
            New-Item -ItemType Directory -Path $script:Config.ReportPath -Force | Out-Null
        }
        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
        $fullPath = Join-Path $script:Config.ReportPath "EventLogReport_$ts.txt"
        $reportText | Set-Content $fullPath -Encoding UTF8
        Write-Host "  [OK] Report saved to: " -ForegroundColor Green -NoNewline
        Write-Host $fullPath -ForegroundColor Cyan
    } catch {
        Write-Host "  [!] Failed to save report: $_" -ForegroundColor Red
    }
}

function Show-ResultsTable {
    param($events)

    if ($null -eq $events -or $events.Count -eq 0) {
        Write-Host ""
        Write-Host "  [!] No events found or access denied." -ForegroundColor Red
        Write-Host "      Try running as Administrator." -ForegroundColor DarkYellow
        return
    }

    $totalCount = $events.Count
    $stats = @{}
    $isWinEvent = $events[0].PSObject.Properties.Name -contains 'LevelDisplayName'

    if ($isWinEvent) {
        ($events | Group-Object LevelDisplayName) | ForEach-Object {
            $n = if ([string]::IsNullOrWhiteSpace($_.Name)) { "Unknown" } else { $_.Name }
            $stats[$n] = $_.Count
        }
        $oldest = ($events | Select-Object -Last 1).TimeCreated
        $newest = ($events | Select-Object -First 1).TimeCreated
    } else {
        ($events | Group-Object EntryType) | ForEach-Object { $stats[$_.Name] = $_.Count }
        $oldest = ($events | Select-Object -Last 1).TimeGenerated
        $newest = ($events | Select-Object -First 1).TimeGenerated
    }

    $colorMap = @{
        "Critical"     = "Red"
        "Error"        = "Red"
        "Warning"      = "Yellow"
        "Information"  = "Cyan"
        "Verbose"      = "DarkGray"
        "Unknown"      = "Gray"
        "FailureAudit" = "Magenta"
        "SuccessAudit" = "Green"
    }
    $iconMap = @{
        "Critical"     = "[CRIT]"
        "Error"        = "[ERR] "
        "Warning"      = "[WARN]"
        "Information"  = "[INFO]"
        "Verbose"      = "[VERB]"
        "Unknown"      = "[ ?? ]"
        "FailureAudit" = "[FAIL]"
        "SuccessAudit" = "[ OK ]"
    }

    Clear-Host
    Show-Title

    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |              SCAN RESULTS  --  SYSTEM LOG                   |" -ForegroundColor DarkCyan
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  Oldest Event : " -ForegroundColor DarkGray -NoNewline
    Write-Host "$oldest" -ForegroundColor White
    Write-Host "  Newest Event : " -ForegroundColor DarkGray -NoNewline
    Write-Host "$newest" -ForegroundColor White
    Write-Host "  Total Events : " -ForegroundColor DarkGray -NoNewline
    Write-Host $totalCount -ForegroundColor Green
    if ($script:Config.MaxEvents -gt 0) {
        Write-Host "  (Scan limited to last $($script:Config.MaxEvents) events -- change in Settings)" -ForegroundColor DarkYellow
    }
    Write-Host ""
    Write-Host "  +-----------------+------------+-----------+----------------------------+" -ForegroundColor DarkGray
    Write-Host "  |  Category       |      Count |   Percent |  Distribution              |" -ForegroundColor White
    Write-Host "  +-----------------+------------+-----------+----------------------------+" -ForegroundColor DarkGray

    $sorted = $stats.GetEnumerator() | Sort-Object Value -Descending
    $maxVal = ($sorted | Select-Object -First 1).Value

    foreach ($entry in $sorted) {
        $name   = $entry.Key
        $count  = $entry.Value
        $pct    = [math]::Round(($count / $totalCount) * 100, 1)
        $barLen = [math]::Round(($count / $maxVal) * 24)
        $bar    = ("=" * $barLen).PadRight(24)
        $clr    = if ($colorMap.ContainsKey($name)) { $colorMap[$name] } else { "White" }
        $icon   = if ($iconMap.ContainsKey($name)) { $iconMap[$name] } else { "[ -- ]" }

        Write-Host "  | " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-15}" -f $icon) -ForegroundColor $clr -NoNewline
        Write-Host "  | " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,9}" -f $count) -ForegroundColor White -NoNewline
        Write-Host "  | " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,6}%" -f $pct) -ForegroundColor DarkYellow -NoNewline
        Write-Host "    | " -ForegroundColor DarkGray -NoNewline
        Write-Host $bar -ForegroundColor $clr -NoNewline
        Write-Host " |" -ForegroundColor DarkGray
    }

    Write-Host "  +-----------------+------------+-----------+----------------------------+" -ForegroundColor DarkGray
    Write-Host "  |  TOTAL          | " -ForegroundColor DarkGray -NoNewline
    Write-Host ("{0,9}" -f $totalCount) -ForegroundColor Green -NoNewline
    Write-Host "  |   100.0%    |                            |" -ForegroundColor DarkGray
    Write-Host "  +-----------------+------------+-----------+----------------------------+" -ForegroundColor DarkGray
    Write-Host ""

    if ($script:Config.SaveReport) {
        $reportText = Build-ReportText -stats $stats -totalCount $totalCount -oldest $oldest -newest $newest
        Save-Report -reportText $reportText
    } else {
        Write-Host "  [i] Report saving is OFF. Enable it in Settings [X]." -ForegroundColor DarkGray
    }
}

function Show-About {
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "      █████╗ ██████╗  ██████╗ ██╗   ██╗████████╗" -ForegroundColor Magenta
        Write-Host "     ██╔══██╗██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝" -ForegroundColor Magenta
        Write-Host "     ███████║██████╔╝██║   ██║██║   ██║   ██║   " -ForegroundColor Magenta
        Write-Host "     ██╔══██║██╔══██╗██║   ██║██║   ██║   ██║   " -ForegroundColor Magenta
        Write-Host "     ██║  ██║██████╔╝╚██████╔╝╚██████╔╝   ██║   " -ForegroundColor Magenta
        Write-Host "     ╚═╝  ╚═╝╚═════╝  ╚═════╝  ╚═════╝    ╚═╝   " -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkMagenta
        Write-Host "  |          Event Log Checker  --  Enhanced Edition            |" -ForegroundColor DarkMagenta
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkMagenta
        Write-Host ""
        Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  This product was originally created as a test for an AI" -ForegroundColor Gray
        Write-Host "  generated code, but after some time I kept adding onto it." -ForegroundColor Gray
        Write-Host ""
        Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Version  : 2.0 -- Enhanced Edition" -ForegroundColor White
        Write-Host "  Platform : Windows PowerShell / PowerShell 7+" -ForegroundColor White
        Write-Host "  Target   : Windows System Event Log" -ForegroundColor White
        Write-Host ""
        Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Execution Policy Note:" -ForegroundColor Yellow
        Write-Host "    This script auto-relaunches itself with ExecutionPolicy Bypass." -ForegroundColor Gray
        Write-Host "    You can also run it manually with:" -ForegroundColor Gray
        Write-Host "    powershell.exe -ExecutionPolicy Bypass -File EventLogChecker.ps1" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  --------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [B] Back   [S] Start Scan   [Q] Quit" -ForegroundColor DarkGray
        Write-Host "  Choice: " -ForegroundColor White -NoNewline
        $ch = (Read-Host).Trim().ToUpper()
        switch ($ch) {
            "B" { return }
            "S" { Run-Scan; return }
            "Q" { Quit-App }
        }
    }
}

function Show-Settings {
    while ($true) {
        Clear-Host
        Show-Title

        $saveLabel = if ($script:Config.SaveReport) { "Enabled  [ON] " } else { "Disabled [OFF]" }
        $saveColor = if ($script:Config.SaveReport) { "Green" } else { "Red" }
        $maxLabel  = if ($script:Config.MaxEvents -eq 0) { "All events (no limit)" } else { "$($script:Config.MaxEvents) most recent" }
        $verbLabel = if ($script:Config.ShowVerbose) { "Shown    [ON] " } else { "Hidden   [OFF]" }
        $verbColor = if ($script:Config.ShowVerbose) { "Green" } else { "DarkGray" }
        $pathDisp  = $script:Config.ReportPath
        if ($pathDisp.Length -gt 36) { $pathDisp = "..." + $pathDisp.Substring($pathDisp.Length - 33) }

        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host "  |                       SETTINGS                              |" -ForegroundColor Magenta
        Write-Host "  +--------------------------------------------------------------+" -ForegroundColor Magenta
        Write-Host ""
        Write-Host "  +------------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host "  |  [1]  Save Report on Scan  : " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-28}" -f $saveLabel) -ForegroundColor $saveColor -NoNewline
        Write-Host "  |" -ForegroundColor DarkGray
        Write-Host "  |  [2]  Report Save Path     : " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-28}" -f $pathDisp) -ForegroundColor Cyan -NoNewline
        Write-Host "  |" -ForegroundColor DarkGray
        Write-Host "  |  [3]  Max Events to Scan   : " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-28}" -f $maxLabel) -ForegroundColor White -NoNewline
        Write-Host "  |" -ForegroundColor DarkGray
        Write-Host "  |  [4]  Show Verbose Events  : " -ForegroundColor DarkGray -NoNewline
        Write-Host ("{0,-28}" -f $verbLabel) -ForegroundColor $verbColor -NoNewline
        Write-Host "  |" -ForegroundColor DarkGray
        Write-Host "  |------------------------------------------------------------|" -ForegroundColor DarkGray
        Write-Host "  |  [R]  Reset to Defaults                                    |" -ForegroundColor DarkGray
        Write-Host "  |  [B]  Back to Main Menu                                    |" -ForegroundColor DarkGray
        Write-Host "  |  [Q]  Quit                                                 |" -ForegroundColor DarkGray
        Write-Host "  +------------------------------------------------------------+" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Config: " -ForegroundColor DarkGray -NoNewline
        Write-Host $script:ConfigPath -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Choice: " -ForegroundColor White -NoNewline
        $ch = (Read-Host).Trim().ToUpper()

        switch ($ch) {
            "1" {
                $script:Config.SaveReport = -not $script:Config.SaveReport
                Save-Config
                Write-Host "  [OK] Save Report toggled to: $($script:Config.SaveReport)" -ForegroundColor Green
                Start-Sleep -Milliseconds 700
            }
            "2" {
                Write-Host ""
                Write-Host "  Current: " -ForegroundColor DarkGray -NoNewline
                Write-Host $script:Config.ReportPath -ForegroundColor Cyan
                Write-Host "  New path (blank = keep current): " -ForegroundColor Yellow -NoNewline
                $newPath = Read-Host
                if ($newPath.Trim() -ne "") {
                    $script:Config.ReportPath = $newPath.Trim()
                    Save-Config
                    Write-Host "  [OK] Path updated." -ForegroundColor Green
                } else {
                    Write-Host "  (No change.)" -ForegroundColor DarkGray
                }
                Start-Sleep -Milliseconds 800
            }
            "3" {
                Write-Host ""
                Write-Host "  Current max: $($script:Config.MaxEvents)  (0 = no limit)" -ForegroundColor DarkGray
                Write-Host "  Enter new max (0 = all): " -ForegroundColor Yellow -NoNewline
                $inp = Read-Host
                if ($inp -match '^\d+$') {
                    $script:Config.MaxEvents = [int]$inp
                    Save-Config
                    Write-Host "  [OK] Max events set to $($script:Config.MaxEvents)." -ForegroundColor Green
                } else {
                    Write-Host "  [!] Invalid. Please enter a number." -ForegroundColor Red
                }
                Start-Sleep -Milliseconds 800
            }
            "4" {
                $script:Config.ShowVerbose = -not $script:Config.ShowVerbose
                Save-Config
                Write-Host "  [OK] Verbose display toggled." -ForegroundColor Green
                Start-Sleep -Milliseconds 700
            }
            "R" {
                $script:Config = @{
                    SaveReport  = $false
                    ReportPath  = [Environment]::GetFolderPath("Desktop")
                    MaxEvents   = 0
                    ShowVerbose = $true
                }
                Save-Config
                Write-Host "  [OK] Settings reset to defaults." -ForegroundColor Green
                Start-Sleep -Milliseconds 800
            }
            "B" { return }
            "Q" { Quit-App }
        }
    }
}

function Run-Scan {
    Clear-Host
    Show-Title
    Write-Host "  Initializing scan of System Event Log..." -ForegroundColor Yellow
    Write-Host ""
    Show-Loading
    $events = Get-SystemEvents
    Show-ResultsTable -events $events
    Write-Host ""
    Write-Host "  [B] Back   [S] Scan Again   [Q] Quit" -ForegroundColor DarkGray
    Write-Host "  Choice: " -ForegroundColor White -NoNewline
    $nav = (Read-Host).Trim().ToUpper()
    switch ($nav) {
        "S" { Run-Scan }
        "Q" { Quit-App }
        default { return }
    }
}

function Quit-App {
    Clear-Host
    Write-Host ""
    Write-Host "  +------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host "  |       Thanks for using Event Log Checker.            |" -ForegroundColor DarkGray
    Write-Host "  |                  Stay secure.                        |" -ForegroundColor DarkGray
    Write-Host "  +------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
    exit
}

# ENTRY POINT
Load-Config
Check-ForUpdates
Show-BootVerbose

while ($true) {
    Show-Title
    Show-Menu
    $choice = (Read-Host).Trim().ToUpper()
    switch ($choice) {
        "S" { Run-Scan }
        "A" { Show-About }
        "X" { Show-Settings }
        "Q" { Quit-App }
        default {
            Write-Host "  [!] Invalid choice. Use S, A, X, or Q." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
