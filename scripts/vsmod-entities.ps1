#Requires -Version 5.1
<#
.SYNOPSIS
    Emits OliveTin entity files describing the state of the modding harness.

.DESCRIPTION
    Strictly read-only: reads harness.json, workspaces\*\workspace.json and the
    cache\ folder, and writes newline-delimited JSON that OliveTin watches.

    Writes into -OutDir:
        workspaces.json   one row per workspace, with the active one flagged
        apis.json         cached vsapi versions
        gamesrc.json      cached game source repos
        deps.json         dependencies linked into the ACTIVE workspace
        examples.json     examples linked into the ACTIVE workspace
        cacheitems.json   every cached item as "<kind>/<name>", for pruning

    Files are written atomically (temp + move) because OliveTin watches them
    for changes and would otherwise occasionally read a half-written file.

.EXAMPLE
    .\vsmod-entities.ps1 -HarnessRoot C:\dev\VSModdingWorkspace -OutDir C:\OliveTin\entities
#>

param(
    [string]$HarnessRoot = "C:/dev/VSModdingWorkspace",
    [string]$OutDir      = "C:/OliveTin/entities"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$CacheDir      = Join-Path $HarnessRoot "cache"
$WorkspacesDir = Join-Path $HarnessRoot "workspaces"
$HarnessJson   = Join-Path $HarnessRoot "harness.json"

if (-not (Test-Path $HarnessRoot)) {
    Write-Host "Harness root not found: $HarnessRoot"
    exit 1
}
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

# ── Helpers ───────────────────────────────────────────────────────────────────
# StrictMode makes reading an absent property a terminating error, and these
# JSON files are user-edited, so every read goes through Get-Prop.
function Get-Prop {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return (Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { Write-Host "  ! unreadable, skipping: $Path"; return $null }
}

function Get-SubdirNames {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    return @(Get-ChildItem $Path -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
}

function Write-EntityFile {
    param([string]$Name, $Rows)
    $target = Join-Path $OutDir $Name
    $tmp    = "$target.tmp"

    $lines = @()
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $lines += ($row | ConvertTo-Json -Compress -Depth 6)
    }

    # An entity with no rows is legitimate (nothing cached yet). Write an empty
    # file rather than deleting, so OliveTin's watcher stays attached to it.
    if ($lines.Count -eq 0) {
        [System.IO.File]::WriteAllText($tmp, "", [System.Text.UTF8Encoding]::new($false))
    } else {
        [System.IO.File]::WriteAllLines($tmp, $lines, [System.Text.UTF8Encoding]::new($false))
    }
    Move-Item $tmp $target -Force
    Write-Host ("  {0,-18} {1} row(s)" -f $Name, $lines.Count)
}

# ── Active workspace ──────────────────────────────────────────────────────────
$harness      = Read-JsonFile $HarnessJson
$activeName   = [string](Get-Prop $harness "activeWorkspace" "")
$activeWsJson = $null
if ($activeName) {
    $activeWsJson = Read-JsonFile (Join-Path (Join-Path $WorkspacesDir $activeName) "workspace.json")
}

Write-Host ""
Write-Host "Harness : $HarnessRoot"
Write-Host "Active  : $(if ($activeName) { $activeName } else { '(none)' })"
Write-Host "Entities:"

# ── workspaces.json ───────────────────────────────────────────────────────────
$workspaceRows = @()
foreach ($name in (Get-SubdirNames $WorkspacesDir)) {
    $wsDir = Join-Path $WorkspacesDir $name
    $ws    = Read-JsonFile (Join-Path $wsDir "workspace.json")
    if ($null -eq $ws) { continue }   # not a workspace, just a stray folder

    $deps     = @(Get-Prop $ws "dependencies" @())
    $examples = @(Get-Prop $ws "examples" @())
    $modDir   = Join-Path $wsDir "mod"

    $workspaceRows += [PSCustomObject]@{
        name         = $name
        modId        = [string](Get-Prop $ws "modId" "")
        modVersion   = [string](Get-Prop $ws "modVersion" "")
        apiVersion   = [string](Get-Prop $ws "apiVersion" "?")
        gameVersion  = [string](Get-Prop $ws "gameVersion" "?")
        dotnetTarget = [string](Get-Prop $ws "dotnetTarget" "")
        active       = $(if ($name -eq $activeName) { "yes" } else { "no" })
        depCount     = [string]$deps.Count
        exampleCount = [string]$examples.Count
        hasGit       = $(if (Test-Path (Join-Path $modDir ".git")) { "yes" } else { "no" })
    }
}
Write-EntityFile "workspaces.json" $workspaceRows

# ── apis.json ─────────────────────────────────────────────────────────────────
$activeApi = ""
if ($null -ne $activeWsJson) { $activeApi = [string](Get-Prop $activeWsJson "apiVersion" "") }

$apiRows = @()
foreach ($v in (Get-SubdirNames (Join-Path $CacheDir "api"))) {
    $apiRows += [PSCustomObject]@{
        version = $v
        active  = $(if ($v -eq $activeApi) { "yes" } else { "no" })
    }
}
Write-EntityFile "apis.json" $apiRows

# ── gamesrc.json ──────────────────────────────────────────────────────────────
$gamesrcRows = @()
foreach ($g in (Get-SubdirNames (Join-Path $CacheDir "gamesrc"))) {
    $gamesrcRows += [PSCustomObject]@{ name = $g }
}
Write-EntityFile "gamesrc.json" $gamesrcRows

# ── deps.json / examples.json (active workspace only) ─────────────────────────
# These drive the remove-dep / remove-example dropdowns, so they must reflect
# what the active workspace actually links, not everything in the cache.
foreach ($pair in @(
    @{ Key = "dependencies"; File = "deps.json" },
    @{ Key = "examples";     File = "examples.json" }
)) {
    $rows = @()
    if ($null -ne $activeWsJson) {
        foreach ($n in @(Get-Prop $activeWsJson $pair.Key @())) {
            if ([string]::IsNullOrWhiteSpace($n)) { continue }
            $rows += [PSCustomObject]@{
                name      = [string]$n
                workspace = $activeName
                cached    = $(if (Test-Path (Join-Path (Join-Path $CacheDir $pair.Key) $n)) { "yes" } else { "missing" })
            }
        }
    }
    Write-EntityFile $pair.File $rows
}

# ── cacheitems.json ───────────────────────────────────────────────────────────
# "ref" is exactly the <kind>/<name> string that `cache remove` expects.
$cacheRows = @()
foreach ($kind in @("api", "gamesrc", "dependencies", "examples")) {
    foreach ($n in (Get-SubdirNames (Join-Path $CacheDir $kind))) {
        $cacheRows += [PSCustomObject]@{
            kind = $kind
            name = $n
            ref  = "$kind/$n"
        }
    }
}
Write-EntityFile "cacheitems.json" $cacheRows

Write-Host ""
exit 0
