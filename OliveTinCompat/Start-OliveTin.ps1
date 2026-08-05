<#
.SYNOPSIS
    One-click launcher for the OliveTin control panel over the VS Modding Harness.

.DESCRIPTION
    Double-click Start-OliveTin.bat rather than running this directly.

    What it does:
      1. Preflight-checks everything that would otherwise fail confusingly later
         (missing pwsh, blocked scripts, absent harness, elevated session).
      2. If OliveTin is already listening, just opens the browser and exits.
      3. Otherwise starts OliveTin in this window so the console doubles as the
         log view, waits for the port, and opens the browser.
      4. Closing the window (or Ctrl+C) stops OliveTin.

.PARAMETER Shortcut
    Creates a desktop shortcut to the .bat and exits without starting anything.

.PARAMETER NoBrowser
    Start OliveTin without opening a browser tab.

.EXAMPLE
    .\Start-OliveTin.bat
    .\Start-OliveTin.bat -Shortcut
#>

param(
    [string]$OliveTinDir = "C:/OliveTin",
    [string]$HarnessRoot = "C:/dev/VSModdingWorkspace",
    [switch]$NoBrowser,
    [switch]$Shortcut
)

$ErrorActionPreference = "Stop"

$script:Problems = 0

function Say     { param($m) Write-Host "  $m" }
function Ok      { param($m) Write-Host "  [ok] " -ForegroundColor Green -NoNewline; Write-Host $m }
function Warn    { param($m) Write-Host "  [--] " -ForegroundColor Yellow -NoNewline; Write-Host $m }
function Fail    { param($m) Write-Host "  [!!] " -ForegroundColor Red -NoNewline; Write-Host $m; $script:Problems++ }
function Section { param($m) Write-Host ""; Write-Host $m -ForegroundColor Cyan }

function Test-Port {
    param([string]$TargetHost, [int]$Port, [int]$TimeoutMs = 400)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($TargetHost, $Port)
        if ($task.Wait($TimeoutMs)) { return $client.Connected }
        return $false
    } catch { return $false } finally { $client.Dispose() }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  OliveTin  -  VS Modding Harness panel" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

$exe        = Join-Path $OliveTinDir "OliveTin.exe"
$configFile = Join-Path $OliveTinDir "config.yaml"
$entities   = Join-Path $OliveTinDir "entities"
$scripts    = Join-Path $HarnessRoot "scripts"

# ── Desktop shortcut mode ─────────────────────────────────────────────────────
if ($Shortcut) {
    Section "Creating desktop shortcut"
    $bat = Join-Path $PSScriptRoot "Start-OliveTin.bat"
    if (-not (Test-Path $bat)) {
        Fail "Start-OliveTin.bat not found next to this script."
        exit 1
    }
    $lnk = Join-Path ([Environment]::GetFolderPath("Desktop")) "OliveTin - Modding Panel.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc  = $wsh.CreateShortcut($lnk)
    $sc.TargetPath       = $bat
    $sc.WorkingDirectory = $PSScriptRoot
    $sc.Description      = "Start the OliveTin control panel for the VS modding harness"
    # Borrow OliveTin's own icon if it has one embedded.
    if (Test-Path $exe) { $sc.IconLocation = "$exe,0" }
    $sc.Save()
    Ok "Created: $lnk"
    Write-Host ""
    exit 0
}

# ── Elevation ─────────────────────────────────────────────────────────────────
Section "Session"
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Warn "Running elevated. Nothing here needs admin, and User Interface Privilege"
    Say  "     Isolation can stop an elevated process showing dialogs on your"
    Say  "     desktop - the Browse buttons may not work. Consider restarting"
    Say  "     this without 'Run as administrator'."
} else {
    Ok "Normal user session (correct - the file dialogs need this)."
}

if (-not [Environment]::UserInteractive) {
    Fail "No desktop attached. The Browse actions cannot work from here."
}

# ── OliveTin install ──────────────────────────────────────────────────────────
Section "OliveTin"
if (Test-Path $exe)        { Ok "OliveTin.exe" }       else { Fail "Not found: $exe" }
if (Test-Path $configFile) { Ok "config.yaml" }        else { Fail "Not found: $configFile" }
if (Test-Path (Join-Path $OliveTinDir "webui")) { Ok "webui\" } else { Warn "No webui\ folder - the UI may not render." }

if (-not (Test-Path $entities)) {
    New-Item -ItemType Directory -Path $entities -Force | Out-Null
    Ok "Created entities\"
} else {
    $n = @(Get-ChildItem $entities -Filter *.json -ErrorAction SilentlyContinue).Count
    Ok "entities\ ($n file(s))"
}

# ── Harness scripts ───────────────────────────────────────────────────────────
Section "Harness"
if (Test-Path (Join-Path $HarnessRoot "harness.json")) {
    Ok "harness.json"
} else {
    Warn "No harness.json in $HarnessRoot - run setup.ps1 in the harness first."
}

foreach ($f in @("vsmod.ps1", "vsmod-web.ps1", "vsmod-entities.ps1", "vsmod-pick.ps1")) {
    if (Test-Path (Join-Path $scripts $f)) { Ok $f } else { Fail "Missing: $scripts\$f" }
}

# Windows marks anything that came from a browser or a zip. A blocked script
# fails under -File with an unhelpful error, so clear it here rather than
# leaving you to guess.
try {
    $blocked = @(Get-ChildItem $scripts -Filter *.ps1 -ErrorAction SilentlyContinue |
                Where-Object { Get-Item $_.FullName -Stream Zone.Identifier -ErrorAction SilentlyContinue })
    if ($blocked.Count -gt 0) {
        $blocked | Unblock-File
        Ok "Unblocked $($blocked.Count) script(s)."
    }
} catch { }

# ── Toolchain ─────────────────────────────────────────────────────────────────
Section "Toolchain"
foreach ($t in @(
    @{ Exe = "pwsh";   Why = "runs every harness action"; Hard = $true  },
    @{ Exe = "git";    Why = "fetching API and game source"; Hard = $false },
    @{ Exe = "dotnet"; Why = "building mods"; Hard = $false }
)) {
    $cmd = Get-Command $t.Exe -ErrorAction SilentlyContinue
    if ($cmd) {
        Ok "$($t.Exe)  -  $($cmd.Source)"
    } elseif ($t.Hard) {
        Fail "$($t.Exe) not on PATH - needed for $($t.Why). Install: winget install Microsoft.PowerShell"
    } else {
        Warn "$($t.Exe) not on PATH - needed for $($t.Why)."
    }
}

if ($script:Problems -gt 0) {
    Write-Host ""
    Write-Host "  $($script:Problems) blocking problem(s). Fix those first." -ForegroundColor Red
    exit 1
}

# ── Port ──────────────────────────────────────────────────────────────────────
# Read the listen address out of config.yaml so this never drifts from it.
$listen = "127.0.0.1:1337"
try {
    $m = Select-String -Path $configFile -Pattern '^\s*listenAddressSingleHTTPFrontend:\s*(\S+)' |
         Select-Object -First 1
    if ($m) { $listen = $m.Matches[0].Groups[1].Value.Trim('"', "'") }
} catch { }

$listenHost, $listenPort = $listen -split ':', 2
if (-not $listenPort) { $listenPort = "1337" }
$browseHost = if ($listenHost -in @("0.0.0.0", "", "::")) { "127.0.0.1" } else { $listenHost }
$url        = "http://${browseHost}:${listenPort}"

# ── Already running? ──────────────────────────────────────────────────────────
Section "Starting"
if (Test-Port -TargetHost $browseHost -Port ([int]$listenPort)) {
    Ok "Already running on $listenPort - opening the browser."
    if (-not $NoBrowser) { Start-Process $url }
    Write-Host ""
    Write-Host "  $url" -ForegroundColor White
    Write-Host ""
    Write-Host "  (This window can be closed. The existing OliveTin keeps running.)" -ForegroundColor DarkGray
    Write-Host ""
    Start-Sleep -Seconds 3
    exit 0
}

# -NoNewWindow so OliveTin's log lands in this console: the window you launched
# from becomes the log view, which is where you look when a build misbehaves.
$proc = Start-Process -FilePath $exe `
                      -WorkingDirectory $OliveTinDir `
                      -NoNewWindow `
                      -PassThru

try {
    $ready = $false
    foreach ($i in 1..40) {
        if ($proc.HasExited) { break }
        if (Test-Port -TargetHost $browseHost -Port ([int]$listenPort)) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }

    if ($proc.HasExited) {
        Write-Host ""
        Fail "OliveTin exited immediately (code $($proc.ExitCode))."
        Say  "     A YAML error in config.yaml is the usual cause - the message"
        Say  "     will be in the output above."
        exit 1
    }

    if (-not $ready) {
        Warn "Port $listenPort did not open within 20s. Still running - check the log above."
    }

    Write-Host ""
    Write-Host "  ---------------------------------------------" -ForegroundColor Green
    Write-Host "   Panel:  $url" -ForegroundColor White
    Write-Host "   Stop:   close this window, or press Ctrl+C" -ForegroundColor DarkGray
    Write-Host "  ---------------------------------------------" -ForegroundColor Green
    Write-Host ""

    if ($ready -and -not $NoBrowser) { Start-Process $url }

    # Block here, streaming OliveTin's log, until it exits or you interrupt.
    Wait-Process -Id $proc.Id
}
finally {
    # Ctrl+C and window-close both land here. Without this, OliveTin would keep
    # holding the port and the next launch would think it was already running.
    if ($null -ne $proc -and -not $proc.HasExited) {
        Write-Host ""
        Write-Host "  Stopping OliveTin..." -ForegroundColor DarkGray
        try { $proc.Kill() } catch { }
    }
}

exit 0
