# Claudia Pet watcher
# Starts claudia-pet.exe when Claude starts, and closes it when Claude exits.
#
#   claudia-watcher.ps1              run the watcher (normally started hidden by claudia-watcher.vbs)
#   claudia-watcher.ps1 -Install     add to Windows startup and start it now
#   claudia-watcher.ps1 -Uninstall   remove from startup and stop the watcher
#   claudia-watcher.ps1 -Check       show what is going on (for troubleshooting)

param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Check
)

# ---------------- settings ----------------
# Which Claude to follow:
#   'both'    = Claude desktop app OR Claude Code (any one running is enough)
#   'desktop' = only the Claude desktop app
#   'code'    = only Claude Code (command line)
$Target = 'both'

# Seconds between checks
$Interval = 3

# Folder of claudia-pet.exe (the script's own folder is tried first)
$DefaultPetDir = 'E:\claudia-pet'
# ------------------------------------------

$ErrorActionPreference = 'SilentlyContinue'

$PetDir = $PSScriptRoot
if (-not (Test-Path (Join-Path $PetDir 'claudia-pet.exe'))) { $PetDir = $DefaultPetDir }
$PetExe = Join-Path $PetDir 'claudia-pet.exe'

$StartupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'ClaudiaPetWatcher.lnk'
$Vbs = Join-Path $PSScriptRoot 'claudia-watcher.vbs'

function Stop-Watchers {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -like '*claudia-watcher.ps1*' -and
            $_.CommandLine -notlike '*-Install*' -and
            $_.CommandLine -notlike '*-Uninstall*'
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
}

if ($Install) {
    if (-not (Test-Path $PetExe)) {
        Write-Host "[X] claudia-pet.exe not found: $PetExe" -ForegroundColor Red
        exit 1
    }
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($StartupLnk)
    $lnk.TargetPath = "$env:SystemRoot\System32\wscript.exe"
    $lnk.Arguments = '"' + $Vbs + '"'
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.Description = 'Claudia Pet watcher'
    $lnk.Save()
    Stop-Watchers
    Start-Process -FilePath "$env:SystemRoot\System32\wscript.exe" -ArgumentList ('"' + $Vbs + '"')
    Write-Host "[OK] Installed. Pet: $PetExe" -ForegroundColor Green
    Write-Host "     Startup shortcut: $StartupLnk"
    exit 0
}

if ($Uninstall) {
    Remove-Item -LiteralPath $StartupLnk -Force
    Stop-Watchers
    Write-Host '[OK] Uninstalled. The watcher is stopped and removed from startup.' -ForegroundColor Green
    exit 0
}

if ($Check) {
    Write-Host '=== Claudia Pet watcher check ==='
    Write-Host ("Script folder : " + $PSScriptRoot)
    Write-Host ("Pet exe       : " + $PetExe + "   exists=" + (Test-Path $PetExe))
    Write-Host ("Startup link  : " + (Test-Path $StartupLnk))
    $w = Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*claudia-watcher.ps1*' -and $_.CommandLine -notlike '*-Check*' }
    Write-Host ("Watcher running: " + [bool]$w)
    Write-Host ("Pet running    : " + [bool](Get-Process -Name 'claudia-pet'))
    Write-Host ''
    Write-Host '--- Processes that look like Claude ---'
    Get-Process | Where-Object { $_.ProcessName -like '*claude*' -or $_.ProcessName -like '*anthropic*' } |
        Select-Object ProcessName, Id, StartTime, Path | Format-Table -AutoSize | Out-String -Width 300 | Write-Host
    Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object { $_.CommandLine -like '*claude*' } |
        ForEach-Object { Write-Host ("node: " + $_.CommandLine) }
    Write-Host '--- Last log lines ---'
    $log = Join-Path $PSScriptRoot 'claudia-watcher.log'
    if (Test-Path $log) { Get-Content -LiteralPath $log -Tail 15 | Write-Host } else { Write-Host '(no log yet)' }
    exit 0
}

# ---------------- watcher ----------------

# Only one watcher at a time
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudiaPetWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

$LogFile = Join-Path $PSScriptRoot 'claudia-watcher.log'
function Write-Log($msg) {
    $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $msg
    Add-Content -LiteralPath $LogFile -Value $line
}

# Returns the newest "launch time" among the Claude apps being followed,
# or $null when none is running. A newer value means Claude was (re)started.
function Get-ClaudeLaunchTime {
    $desktop = $null
    $code = $null

    # Claude.exe is used by both the desktop app and the native Claude Code install.
    # Native Claude Code lives under ...\.local\bin\claude.exe; anything else is the desktop app.
    foreach ($p in (Get-Process -Name 'claude')) {
        $t = $p.StartTime
        if (-not $t) { $t = Get-Date }
        if ($p.Path -like '*\.local\*') {
            if (-not $code -or $t -lt $code) { $code = $t }
        } else {
            if (-not $desktop -or $t -lt $desktop) { $desktop = $t }
        }
    }

    # Claude Code installed with npm runs inside node.exe
    if ($Target -ne 'desktop') {
        $nodes = Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
            Where-Object { $_.CommandLine -like '*claude-code*' }
        foreach ($n in $nodes) {
            $t = $n.CreationDate
            if (-not $code -or $t -lt $code) { $code = $t }
        }
    }

    switch ($Target) {
        'desktop' { return $desktop }
        'code'    { return $code }
        default {
            if ($desktop -and $code) { if ($desktop -gt $code) { return $desktop } else { return $code } }
            if ($desktop) { return $desktop }
            return $code
        }
    }
}

function Start-Pet {
    if (Get-Process -Name 'claudia-pet') { Write-Log 'Pet already running'; return }
    if (-not (Test-Path $PetExe)) { Write-Log "ERROR: pet not found: $PetExe"; return }
    Start-Process -FilePath $PetExe -WorkingDirectory $PetDir
    Write-Log "Pet started: $PetExe"
}

function Stop-Pet {
    $pets = Get-Process -Name 'claudia-pet'
    if (-not $pets) { return }
    foreach ($p in $pets) { [void]$p.CloseMainWindow() }   # ask nicely first
    Start-Sleep -Seconds 3
    Get-Process -Name 'claudia-pet' | Stop-Process -Force  # then force
    Write-Log 'Pet closed'
}

Write-Log "Watcher started. Target=$Target Pet=$PetExe"

$lastLaunch = $null   # launch time of the Claude we already handled
$offCount = 0

while ($true) {
    $launch = Get-ClaudeLaunchTime

    if ($launch) {
        $offCount = 0
        # Claude was just opened or restarted -> start the pet.
        # (If you close the pet yourself while Claude stays open, it stays closed.)
        if (-not $lastLaunch -or $launch -gt $lastLaunch) {
            Write-Log "Claude detected (started $launch)"
            Start-Pet
        }
        $lastLaunch = $launch
    }
    elseif ($lastLaunch) {
        # Wait for 2 checks in a row so a short gap does not close the pet
        $offCount++
        if ($offCount -ge 2) {
            Write-Log 'Claude closed'
            Stop-Pet
            $lastLaunch = $null
            $offCount = 0
        }
    }

    Start-Sleep -Seconds $Interval
}
