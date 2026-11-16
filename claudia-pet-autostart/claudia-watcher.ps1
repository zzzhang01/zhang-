# Claudia Pet watcher
# Starts claudia-pet.exe when Claude starts, and closes it when Claude exits.
#
#   claudia-watcher.ps1              run the watcher (normally started hidden by claudia-watcher.vbs)
#   claudia-watcher.ps1 -Install     add to Windows startup and start it now
#   claudia-watcher.ps1 -Uninstall   remove from startup and stop the watcher

param(
    [switch]$Install,
    [switch]$Uninstall
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

# ---------------- watcher ----------------

# Only one watcher at a time
$createdNew = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\ClaudiaPetWatcher', [ref]$createdNew)
if (-not $createdNew) { exit 0 }

function Test-ClaudeRunning {
    $desktop = $false
    $code = $false

    # Claude.exe is used by both the desktop app and the native Claude Code install.
    # Native Claude Code lives under ...\.local\bin\claude.exe; anything else is the desktop app.
    foreach ($p in (Get-Process -Name 'claude')) {
        if ($p.Path -like '*\.local\*') { $code = $true } else { $desktop = $true }
    }

    # Claude Code installed with npm runs inside node.exe
    if (-not $code -and $Target -ne 'desktop') {
        $node = Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
            Where-Object { $_.CommandLine -like '*claude-code*' }
        if ($node) { $code = $true }
    }

    switch ($Target) {
        'desktop' { return $desktop }
        'code'    { return $code }
        default   { return ($desktop -or $code) }
    }
}

function Start-Pet {
    if (-not (Get-Process -Name 'claudia-pet')) {
        Start-Process -FilePath $PetExe -WorkingDirectory $PetDir
    }
}

function Stop-Pet {
    $pets = Get-Process -Name 'claudia-pet'
    if (-not $pets) { return }
    foreach ($p in $pets) { [void]$p.CloseMainWindow() }   # ask nicely first
    Start-Sleep -Seconds 3
    Get-Process -Name 'claudia-pet' | Stop-Process -Force  # then force
}

$wasRunning = $false
$offCount = 0

while ($true) {
    $isRunning = Test-ClaudeRunning

    if ($isRunning) {
        $offCount = 0
        # Claude just opened -> start the pet.
        # (If you close the pet yourself while Claude is open, it stays closed.)
        if (-not $wasRunning) { Start-Pet }
        $wasRunning = $true
    }
    elseif ($wasRunning) {
        # Wait for 2 checks in a row so a quick Claude restart/update does not close the pet
        $offCount++
        if ($offCount -ge 2) {
            Stop-Pet
            $wasRunning = $false
            $offCount = 0
        }
    }

    Start-Sleep -Seconds $Interval
}
