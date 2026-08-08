#Requires -Version 5.1
<#
.SYNOPSIS
    Vintage Story Modding Harness - workspace manager.
.DESCRIPTION
    Manages isolated per-mod workspaces, a shared download cache, mod scaffolding,
    mod import, and builds. Agent-agnostic: no editor or AI-vendor coupling.
    No external dependencies beyond git and the .NET SDK.
.EXAMPLE
    .\scripts\vsmod.ps1 init
    .\scripts\vsmod.ps1 new GlowingMushroom
    .\scripts\vsmod.ps1 import https://github.com/someone/TheirMod.git
    .\scripts\vsmod.ps1 use GlowingMushroom
    .\scripts\vsmod.ps1 build release
#>

# No param() block - PS 5.1 parameter binding chokes on dotted version strings
# like "1.21.5". Read the automatic $args variable directly instead.
$Command = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$CmdArgs = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root          = Split-Path $PSScriptRoot -Parent
$HarnessJson   = Join-Path $Root "harness.json"
$CacheDir      = Join-Path $Root "cache"
$WorkspacesDir = Join-Path $Root "workspaces"

# ─── Output helpers ───────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "i " -ForegroundColor Cyan   -NoNewline; Write-Host $msg }
function Write-Success  { param($msg) Write-Host "v " -ForegroundColor Green  -NoNewline; Write-Host $msg }
function Write-Warn    { param($msg) Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err     { param($msg) Write-Host "x " -ForegroundColor Red    -NoNewline; Write-Host $msg }
function Write-Header  { param($msg) Write-Host "`n-- $msg --" -ForegroundColor Cyan }

# ─── PS 5.1 compat helpers ────────────────────────────────────────────────────
# PowerShell 5.1 (the Windows built-in) lacks the ?? operator and errors under
# StrictMode when reading a property that does not exist. These smooth that over.
function Coalesce { param($a, $b) if ($null -ne $a -and $a -ne '') { $a } else { $b } }
function ArgAt    { param($arr, $idx, $default = '') $a = @($arr); if ($a.Count -gt $idx) { $a[$idx] } else { $default } }

function Get-Prop {
    param($obj, [string]$Name, $Default = $null)
    if ($null -eq $obj) { return $Default }
    $p = $obj.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Get-PropArray {
    param($obj, [string]$Name)
    $v = Get-Prop $obj $Name @()
    # Callers that need .Count must wrap the result in @(), because PowerShell
    # unrolls a single-element array on return. Returning ,$arr instead would
    # make @(Get-PropArray ...) an array-of-array, which is a nastier trap.
    return @($v | Where-Object { $null -ne $_ -and $_ -ne '' })
}

# PS 5.1 serialises an empty @() as null. Patch the known array keys back to [].
function Save-Json {
    param($Object, [string]$Path)
    $json = $Object | ConvertTo-Json -Depth 12
    foreach ($key in @('dependencies', 'examples', 'gamesrc', 'authors')) {
        $json = $json -replace "`"$key`":\s*null", "`"$key`": []"
    }
    $json | Set-Content $Path -Encoding UTF8
}

# ─── Platform detection ───────────────────────────────────────────────────────
# $IsWindows only exists on PS 6+; on 5.1 the platform is always Windows.
$Script:OnWindows = $true
$isWinVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
if ($null -ne $isWinVar) { $Script:OnWindows = [bool]$isWinVar.Value }

# ─── Directory link helpers ───────────────────────────────────────────────────
# Workspaces link to the shared cache instead of copying it. On Windows a
# junction is used because it needs no admin rights and no developer mode.
function Test-DirLink {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $false }
    try {
        $item = Get-Item $Path -Force
        return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
    } catch { return $false }
}

function Remove-DirLink {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    if (Test-DirLink $Path) {
        # Delete the link itself, never recurse into the target.
        [System.IO.Directory]::Delete($Path, $false)
    } else {
        Remove-Item $Path -Recurse -Force
    }
}

function New-DirLink {
    param([string]$LinkPath, [string]$TargetPath)

    if (-not (Test-Path $TargetPath)) { return $false }

    # Already correctly linked? Leave it alone - this keeps 'use' instant.
    if (Test-DirLink $LinkPath) {
        try {
            $existing = (Get-Item $LinkPath -Force).Target
            if ($existing -and (@($existing)[0] -replace '[\\/]+$', '') -eq ($TargetPath -replace '[\\/]+$', '')) {
                return $true
            }
        } catch { }
        Remove-DirLink $LinkPath
    } elseif (Test-Path $LinkPath) {
        # A real directory sits where the link should be. Never silently delete
        # user data - report and skip.
        Write-Warn "Not a link, leaving untouched: $LinkPath"
        return $false
    }

    $parent = Split-Path $LinkPath -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    try {
        if ($Script:OnWindows) {
            New-Item -ItemType Junction -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        } else {
            New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -ErrorAction Stop | Out-Null
        }
        return $true
    } catch {
        Write-Warn "Could not link $LinkPath -> $TargetPath"
        Write-Info "  $($_.Exception.Message)"
        return $false
    }
}

# ─── Harness config (global, machine-level) ───────────────────────────────────
function Get-Harness {
    if (-not (Test-Path $HarnessJson)) {
        $example = Join-Path $Root "harness.example.json"
        if (Test-Path $example) {
            Copy-Item $example $HarnessJson
            Write-Info "Created harness.json from harness.example.json - edit gameDirectory in it."
        } else {
            Write-Err "harness.json not found and no harness.example.json to copy."
            exit 1
        }
    }
    return (Get-Content $HarnessJson -Raw | ConvertFrom-Json)
}

function Save-Harness { param($h) Save-Json $h $HarnessJson }

function Get-DefaultsValue {
    param([string]$Key, $Fallback)
    $h = Get-Harness
    $d = Get-Prop $h 'defaults'
    return (Coalesce (Get-Prop $d $Key) $Fallback)
}

# ─── Workspace resolution ─────────────────────────────────────────────────────
function Get-ActiveName {
    $h = Get-Harness
    return (Get-Prop $h 'activeWorkspace')
}

function Get-WorkspaceDir {
    param([string]$Name)
    return (Join-Path $WorkspacesDir $Name)
}

function Test-WorkspaceExists {
    param([string]$Name)
    if (-not $Name) { return $false }
    return (Test-Path (Join-Path (Get-WorkspaceDir $Name) "workspace.json"))
}

function Get-ActiveWorkspaceDir {
    param([switch]$Quiet)
    $name = Get-ActiveName
    if (-not $name) {
        if (-not $Quiet) {
            Write-Err "No active workspace."
            Write-Info "Pick one:      .\scripts\vsmod.ps1 use <Name>"
            Write-Info "See them all:  .\scripts\vsmod.ps1 list"
            Write-Info "Make one:      .\scripts\vsmod.ps1 new <ModName>"
        }
        return $null
    }
    if (-not (Test-WorkspaceExists $name)) {
        if (-not $Quiet) {
            Write-Err "Active workspace '$name' no longer exists on disk."
            Write-Info "Run: .\scripts\vsmod.ps1 list"
        }
        return $null
    }
    return (Get-WorkspaceDir $name)
}

function Get-Workspace {
    param([string]$Name = "")
    if (-not $Name) {
        $dir = Get-ActiveWorkspaceDir
        if (-not $dir) { exit 1 }
    } else {
        $dir = Get-WorkspaceDir $Name
        if (-not (Test-Path (Join-Path $dir "workspace.json"))) {
            Write-Err "Workspace not found: $Name"; exit 1
        }
    }
    $ws = Get-Content (Join-Path $dir "workspace.json") -Raw | ConvertFrom-Json
    $ws | Add-Member -NotePropertyName '_dir' -NotePropertyValue $dir -Force
    return $ws
}

function Save-Workspace {
    param($ws)
    $dir = $ws._dir
    $copy = $ws | Select-Object -Property * -ExcludeProperty '_dir'
    Save-Json $copy (Join-Path $dir "workspace.json")
}

# Game directory: workspace override first, then the harness default.
function Resolve-GameDirectory {
    param($ws)
    $gd = Get-Prop $ws 'gameDirectory'
    if (-not $gd) { $gd = Get-Prop (Get-Harness) 'gameDirectory' }
    if (-not $gd) { return "" }
    return [System.Environment]::ExpandEnvironmentVariables($gd)
}

# A game path can be malformed, on an unplugged drive, or written for another OS.
# Probing must never take the whole command down with it.
function Test-GameInstall {
    param([string]$GameDir)
    if (-not $GameDir) { return $false }
    try {
        $dll = [System.IO.Path]::Combine($GameDir, "VintagestoryAPI.dll")
        return [System.IO.File]::Exists($dll)
    } catch { return $false }
}

function Get-ModDir {
    param($ws)
    return (Join-Path $ws._dir "mod")
}

# ─── Shared cache ─────────────────────────────────────────────────────────────
# Everything downloaded lives here exactly once. Workspaces link to it, so
# switching between mods never re-downloads and never re-copies anything.
function Get-CachePath {
    param([string]$Kind, [string]$Name)
    return (Join-Path (Join-Path $CacheDir $Kind) $Name)
}

function Initialize-Cache {
    foreach ($k in @("api", "gamesrc", "dependencies", "examples")) {
        $p = Join-Path $CacheDir $k
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    }
}

# Finds the commit in a cloned repo that best matches a requested version.
# Exact string match first; otherwise the highest version at or below the
# request, falling back to the lowest above it. $null if no versions exist.
function Find-VersionCommit {
    param([string]$RepoPath, [string]$Label)

    $label = $Label.TrimStart("v")
    $logOutput = @(git -C $RepoPath log --format="%H %s" 2>&1 |
                   Where-Object { $_ -notmatch '^fatal:' })
    if ($logOutput.Count -eq 0) { return $null }

    $exactLine = $logOutput |
                 Where-Object { $_ -match [regex]::Escape($label) } |
                 Select-Object -First 1
    if ($exactLine) {
        $hash  = ($exactLine -split '\s+')[0]
        $parts = $exactLine -split '\s+', 2
        $subj  = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
        return [PSCustomObject]@{ Hash = $hash; Subject = $subj; MatchedVersion = $label; IsExact = $true }
    }

    $reqVer = $null
    try { $reqVer = [System.Version]$label } catch { return $null }

    $versionRx  = [regex]'\b(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b'
    $seen       = @{}
    $candidates = New-Object 'System.Collections.Generic.List[object]'

    foreach ($line in $logOutput) {
        foreach ($m in $versionRx.Matches($line)) {
            $verStr = $m.Value
            if ($seen.ContainsKey($verStr)) { continue }
            $ver = $null
            try { $ver = [System.Version]$verStr } catch { continue }
            $seen[$verStr] = $true
            $hash  = ($line -split '\s+')[0]
            $parts = $line -split '\s+', 2
            $subj  = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
            $candidates.Add([PSCustomObject]@{ Hash = $hash; Subject = $subj; Version = $ver; VersionStr = $verStr })
        }
    }
    if ($candidates.Count -eq 0) { return $null }

    $below   = @($candidates | Where-Object { $_.Version -le $reqVer } | Sort-Object Version -Descending)
    $above   = @($candidates | Where-Object { $_.Version -gt $reqVer } | Sort-Object Version)
    $ordered = @($below) + @($above)
    if ($ordered.Count -eq 0) { return $null }

    $best = $ordered[0]
    return [PSCustomObject]@{
        Hash = $best.Hash; Subject = $best.Subject
        MatchedVersion = $best.VersionStr; IsExact = $false
    }
}

$Script:KnownGameSrcRepos = @{
    "essentials" = "https://github.com/anegostudios/vsessentialsmod.git"
    "survival"   = "https://github.com/anegostudios/vssurvivalmod.git"
    "creative"   = "https://github.com/anegostudios/vscreativemod.git"
}

# Fetch vsapi source into the cache. Idempotent - a cached version is reused.
function Get-CachedApi {
    param([string]$Version)
    Initialize-Cache
    $label = $Version.TrimStart("v")
    $dest  = Get-CachePath "api" $label

    if (Test-Path $dest) { return $dest }

    Write-Info "Cloning vsapi $label into the shared cache (one time only)..."
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $repo = Join-Path $dest "vsapi"

    git clone https://github.com/anegostudios/vsapi.git $repo
    if ($LASTEXITCODE -ne 0) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue; Write-Err "git clone failed."; return $null }

    $result = Find-VersionCommit $repo $label
    if ($result) {
        if (-not $result.IsExact) {
            Write-Warn "Exact version '$label' not found -- closest match: $($result.MatchedVersion)"
        }
        Write-Info "Commit: $($result.Subject)"
        git -C $repo checkout $result.Hash --quiet
        Write-Success "Cached vsapi at $($result.MatchedVersion) (commit $($result.Hash.Substring(0,7)))"
    } else {
        Write-Warn "No version commits found -- cached vsapi at latest master HEAD."
    }
    return $dest
}

function Get-CachedGameSrc {
    param([string]$Name, [string]$Version = "")
    Initialize-Cache
    $Name = $Name.ToLower()

    if (-not $Script:KnownGameSrcRepos.ContainsKey($Name)) {
        Write-Err "Unknown game source repo: '$Name'"
        Write-Info "Known: $($Script:KnownGameSrcRepos.Keys -join ', ')"
        return $null
    }

    $key  = if ($Version) { "$Name-$($Version.TrimStart('v'))" } else { $Name }
    $dest = Get-CachePath "gamesrc" $key
    if (Test-Path $dest) { return $dest }

    $url = $Script:KnownGameSrcRepos[$Name]
    Write-Info "Cloning $Name into the shared cache (one time only)..."
    git clone $url $dest
    if ($LASTEXITCODE -ne 0) { Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue; Write-Err "git clone failed."; return $null }

    if ($Version) {
        $result = Find-VersionCommit $dest $Version.TrimStart("v")
        if ($result) {
            if (-not $result.IsExact) { Write-Warn "Closest match: $($result.MatchedVersion)" }
            git -C $dest checkout $result.Hash --quiet
            Write-Success "Cached $Name at $($result.MatchedVersion)"
        } else {
            Write-Warn "No version commits found -- cached at latest master HEAD."
        }
    } else {
        Write-Success "Cached $Name at latest master HEAD"
    }
    return $dest
}

# Pull a dependency or example mod (git URL or local path) into the cache.
function Get-CachedContext {
    param([string]$Kind, [string]$Name, [string]$Source)
    Initialize-Cache
    $dest = Get-CachePath $Kind $Name
    if (Test-Path $dest) { Write-Info "Already cached: cache/$Kind/$Name"; return $dest }

    if ($Source -match "^https?://" -or $Source -match "^git@") {
        Write-Info "Cloning $Source into the shared cache..."
        git clone --depth 1 $Source $dest
        if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; return $null }
    } elseif (Test-Path $Source) {
        Write-Info "Copying $Source into the shared cache..."
        Copy-Item -Recurse $Source $dest
    } else {
        Write-Err "Source not found and not a URL: $Source"
        return $null
    }
    return $dest
}

# ─── Workspace link sync ──────────────────────────────────────────────────────
# Rebuilds a workspace's links from its own workspace.json manifest. Runs on
# every 'use', which makes switching self-healing and effectively free: an
# already-correct link is left alone, and nothing is downloaded again.
function Sync-WorkspaceLinks {
    param($ws, [switch]$Quiet)

    $dir     = $ws._dir
    $created = 0
    $missing = New-Object 'System.Collections.Generic.List[string]'

    # api/ -> cache/api/{version}
    $apiVersion = Get-Prop $ws 'apiVersion'
    $apiLink    = Join-Path $dir "api"
    if ($apiVersion) {
        $target = Get-CachePath "api" $apiVersion
        if (Test-Path $target) {
            if (New-DirLink $apiLink $target) { $created++ }
        } else {
            $missing.Add("api $apiVersion  ->  fetch-api $apiVersion")
        }
    }

    # gamesrc/{name}, dependencies/{name}, examples/{name}
    $groups = @(
        @{ Key = 'gamesrc';      Folder = 'gamesrc';      Hint = 'fetch-gamesrc' },
        @{ Key = 'dependencies'; Folder = 'dependencies'; Hint = 'add-dep' },
        @{ Key = 'examples';     Folder = 'examples';     Hint = 'add-example' }
    )

    foreach ($g in $groups) {
        $groupDir = Join-Path $dir $g.Folder
        if (-not (Test-Path $groupDir)) { New-Item -ItemType Directory -Path $groupDir -Force | Out-Null }

        $wanted = @(Get-PropArray $ws $g.Key)

        # Drop links that are no longer in the manifest.
        foreach ($child in @(Get-ChildItem $groupDir -Force -ErrorAction SilentlyContinue)) {
            if ((Test-DirLink $child.FullName) -and ($wanted -notcontains $child.Name)) {
                Remove-DirLink $child.FullName
            }
        }

        foreach ($name in $wanted) {
            $target = Get-CachePath $g.Key $name
            if (Test-Path $target) {
                if (New-DirLink (Join-Path $groupDir $name) $target) { $created++ }
            } else {
                $missing.Add("$($g.Key) $name  ->  $($g.Hint) ...")
            }
        }
    }

    if (-not $Quiet) {
        if ($missing.Count -gt 0) {
            Write-Warn "Not in the cache yet:"
            foreach ($m in $missing) { Write-Host "    $m" -ForegroundColor Yellow }
        }
    }
    return $created
}

# ─── init ─────────────────────────────────────────────────────────────────────
function Invoke-Init {
    Write-Header "Initialising harness"
    Initialize-Cache
    if (-not (Test-Path $WorkspacesDir)) { New-Item -ItemType Directory -Path $WorkspacesDir -Force | Out-Null }
    Get-Harness | Out-Null

    Write-Success "cache/ and workspaces/ ready."
    Write-Host ""

    $gd = Get-Prop (Get-Harness) 'gameDirectory'
    $gdExpanded = if ($gd) { [System.Environment]::ExpandEnvironmentVariables($gd) } else { "" }
    if (Test-GameInstall $gdExpanded) {
        Write-Success "Game install found: $gdExpanded"
    } else {
        Write-Warn "Set 'gameDirectory' in harness.json to your Vintage Story install folder."
        if ($gd) { Write-Info "Current value does not contain VintagestoryAPI.dll: $gd" }
    }

    Write-Host ""
    Write-Host "  Next:" -ForegroundColor White
    Write-Host "    .\scripts\vsmod.ps1 fetch-api 1.21.5      " -NoNewline -ForegroundColor Cyan
    Write-Host "download the API source once"
    Write-Host "    .\scripts\vsmod.ps1 new MyMod             " -NoNewline -ForegroundColor Cyan
    Write-Host "create a mod workspace"
    Write-Host "    .\scripts\vsmod.ps1 import <path-or-url>  " -NoNewline -ForegroundColor Cyan
    Write-Host "bring in an existing mod"
    Write-Host ""
}

# ─── use / list / remove ──────────────────────────────────────────────────────
function Invoke-Use {
    param([string]$Name)

    if (-not $Name) {
        Write-Err "Usage: use <WorkspaceName>"
        Invoke-List
        exit 1
    }

    if (-not (Test-WorkspaceExists $Name)) {
        # Case-insensitive rescue: people type 'mymod' for 'MyMod'.
        $match = @(Get-ChildItem $WorkspacesDir -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -ieq $Name })
        if ($match.Count -eq 1) {
            $Name = $match[0].Name
        } else {
            Write-Err "No workspace named '$Name'."
            Invoke-List
            exit 1
        }
    }

    $h = Get-Harness
    $h.activeWorkspace = $Name
    Save-Harness $h

    $ws = Get-Workspace $Name
    Sync-WorkspaceLinks $ws | Out-Null

    Write-Success "Active workspace: $Name"
    Write-Info "Mod repo:  workspaces/$Name/mod/"
    Write-Info "API:       $(Coalesce (Get-Prop $ws 'apiVersion') 'unset')   Game: $(Coalesce (Get-Prop $ws 'gameVersion') 'unset')"
}

function Invoke-List {
    Write-Header "Workspaces"
    if (-not (Test-Path $WorkspacesDir)) { Write-Warn "None yet. Run: new <ModName>"; return }

    $active = Get-ActiveName
    $dirs   = @(Get-ChildItem $WorkspacesDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { Test-Path (Join-Path $_.FullName "workspace.json") })

    if ($dirs.Count -eq 0) {
        Write-Warn "None yet."
        Write-Info "Create one:  .\scripts\vsmod.ps1 new <ModName>"
        Write-Info "Or import:   .\scripts\vsmod.ps1 import <path-or-url>"
        return
    }

    foreach ($d in $dirs) {
        $ws  = Get-Content (Join-Path $d.FullName "workspace.json") -Raw | ConvertFrom-Json
        $api = Coalesce (Get-Prop $ws 'apiVersion') '?'
        $ver = Coalesce (Get-Prop $ws 'modVersion') ''
        $tag = if ($ver) { " v$ver" } else { "" }
        if ($d.Name -eq $active) {
            Write-Host "  * $($d.Name)$tag" -ForegroundColor Green -NoNewline
            Write-Host "   (active, VS $api)"
        } else {
            Write-Host "  o $($d.Name)$tag" -NoNewline
            Write-Host "   (VS $api)"
        }
    }
    Write-Host ""
    Write-Info "Switch with: .\scripts\vsmod.ps1 use <Name>"
}

function Invoke-Remove {
    param([string]$Name)
    if (-not $Name) { Write-Err "Usage: remove <WorkspaceName>"; exit 1 }
    if (-not (Test-WorkspaceExists $Name)) { Write-Err "No workspace named '$Name'."; exit 1 }

    $dir    = Get-WorkspaceDir $Name
    $modDir = Join-Path $dir "mod"

    Write-Warn "This deletes workspaces/$Name/ including the mod source at mod/."
    if (Test-Path (Join-Path $modDir ".git")) {
        $unpushed = git -C $modDir status --porcelain 2>&1
        if ($unpushed) { Write-Warn "The mod repo has uncommitted changes." }
    }
    Write-Info "The shared cache is not touched."
    $confirm = Read-Host "Type the workspace name to confirm deletion"
    if ($confirm -ne $Name) { Write-Info "Cancelled."; return }

    # Remove links first so no junction is ever followed into the cache.
    foreach ($sub in @("api", "gamesrc", "dependencies", "examples")) {
        $p = Join-Path $dir $sub
        if (Test-DirLink $p) { Remove-DirLink $p }
        elseif (Test-Path $p) {
            foreach ($child in @(Get-ChildItem $p -Force -ErrorAction SilentlyContinue)) {
                if (Test-DirLink $child.FullName) { Remove-DirLink $child.FullName }
            }
        }
    }
    Remove-Item $dir -Recurse -Force

    $h = Get-Harness
    if ((Get-Prop $h 'activeWorkspace') -eq $Name) { $h.activeWorkspace = $null; Save-Harness $h }
    Write-Success "Removed workspace: $Name"
}

function Invoke-Sync {
    $ws = Get-Workspace
    Write-Header "Syncing links for $(Split-Path $ws._dir -Leaf)"
    $n = Sync-WorkspaceLinks $ws
    Write-Success "$n link(s) in place."
}

# ─── status ───────────────────────────────────────────────────────────────────
function Invoke-Status {
    Write-Header "Harness Status"

    $h    = Get-Harness
    $name = Get-ActiveName

    Write-Host "  Harness root:   " -NoNewline; Write-Host $Root -ForegroundColor White
    Write-Host "  Shared cache:   " -NoNewline; Write-Host $CacheDir -ForegroundColor White
    Write-Host "  Active:         " -NoNewline
    if ($name) { Write-Host $name -ForegroundColor White } else { Write-Host "! none -- run: use <Name>" -ForegroundColor Yellow }

    if (-not $name -or -not (Test-WorkspaceExists $name)) {
        Write-Host ""
        Invoke-List
        return
    }

    $ws     = Get-Workspace
    $dir    = $ws._dir
    $modDir = Get-ModDir $ws

    Write-Host ""
    Write-Host "  Mod name:       " -NoNewline; Write-Host (Coalesce (Get-Prop $ws 'modName') '?') -ForegroundColor White
    Write-Host "  Mod id:         " -NoNewline; Write-Host (Coalesce (Get-Prop $ws 'modId') '?') -ForegroundColor White
    Write-Host "  Game version:   " -NoNewline; Write-Host (Coalesce (Get-Prop $ws 'gameVersion') 'unset') -ForegroundColor White
    Write-Host "  API version:    " -NoNewline; Write-Host (Coalesce (Get-Prop $ws 'apiVersion') 'unset') -ForegroundColor White
    Write-Host "  .NET target:    " -NoNewline; Write-Host (Coalesce (Get-Prop $ws 'dotnetTarget') 'unset') -ForegroundColor White

    $gd = Resolve-GameDirectory $ws
    Write-Host "  Game directory: " -NoNewline; Write-Host (Coalesce $gd 'unset') -ForegroundColor White
    if ($gd) {
        if (Test-GameInstall $gd) { Write-Success "Game install found." }
        else { Write-Warn "VintagestoryAPI.dll not found there." }
    }

    Write-Host ""
    Write-Host "  Mod repo (workspaces\$name\mod\):" -ForegroundColor Cyan
    if (Test-Path (Join-Path $modDir ".git")) {
        $branch = (git -C $modDir rev-parse --abbrev-ref HEAD 2>&1)
        $dirty  = @(git -C $modDir status --porcelain 2>&1)
        Write-Host "    git branch:   $branch"
        if ($dirty.Count -gt 0) { Write-Host "    $($dirty.Count) uncommitted change(s)" -ForegroundColor Yellow }
        else { Write-Host "    clean" -ForegroundColor Green }
        $remotes = @(git -C $modDir remote 2>&1 | Where-Object { $_ })
        if ($remotes.Count -eq 0) { Write-Host "    no remote (push by hand after copying it out)" }
        else { Write-Host "    remote: $($remotes -join ', ')" }
    } else {
        Write-Warn "  Not a git repo. Run: git-init"
    }

    Write-Host ""
    Write-Host "  Linked context:" -ForegroundColor Cyan
    $apiLink = Join-Path $dir "api"
    if (Test-Path $apiLink) { Write-Host "    v api/            -> cache/api/$(Get-Prop $ws 'apiVersion')" -ForegroundColor Green }
    else { Write-Host "    x api/            (run: fetch-api $(Get-Prop $ws 'apiVersion'))" -ForegroundColor Red }

    foreach ($g in @('gamesrc', 'dependencies', 'examples')) {
        $items = @(Get-PropArray $ws $g)
        if ($items.Count -eq 0) { Write-Host "    - $g/  (none)"; continue }
        foreach ($i in $items) {
            if (-not $i) { continue }
            $p = Join-Path (Join-Path $dir $g) ([string]$i)
            if (Test-Path $p) { Write-Host "    v $g/$i" -ForegroundColor Green }
            else { Write-Host "    x $g/$i  (not cached)" -ForegroundColor Red }
        }
    }
    Write-Host ""
}

# ─── Scaffold templates ───────────────────────────────────────────────────────
# Single-quoted here-strings: nothing is interpolated by PowerShell, so MSBuild's
# own $(...) syntax survives untouched. Tokens below are swapped in afterwards.

$Script:TplGitignore = @'
# Build output
bin/
obj/
Releases/

# Machine-specific paths (copy localSettings.props.template -> localSettings.props)
Properties/localSettings.props

# Editors
.vs/
.vscode/
.idea/
*.user
*.suo

# OS noise
Thumbs.db
.DS_Store
'@

$Script:TplDirectoryBuildProps = @'
<Project>
  <!--
    Directory.Build.props - mod identity and shared compiler settings.
    MSBuild imports this automatically before every .csproj in this folder.
    Edit ModName / ModVersion / Description / Side here; modinfo.json is
    generated from these values at build time.
  -->

  <PropertyGroup>
    <ModName>__MODNAME__</ModName>
    <ModType>code</ModType>
    <ModVersion>1.0.0</ModVersion>
    <ModId>__MODID__</ModId>
    <Description>A Vintage Story mod.</Description>
    <Side>universal</Side>
    <RequiredOnClient>true</RequiredOnClient>
    <RequiredOnServer>true</RequiredOnServer>
  </PropertyGroup>

  <ItemGroup>
    <ModInfoAuthors Include="__AUTHOR__" />
  </ItemGroup>

  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <AppendRuntimeIdentifierToOutputPath>false</AppendRuntimeIdentifierToOutputPath>
  </PropertyGroup>

  <PropertyGroup>
    <ProjectDir>$(MSBuildProjectDirectory)</ProjectDir>
    <AssetsDir>$(ProjectDir)/resources/assets</AssetsDir>
    <!-- Drop extra DLLs into external/ and they are referenced automatically -->
    <ExternalLibDir>$(ProjectDir)/external</ExternalLibDir>
  </PropertyGroup>

  <!-- Machine-specific path overrides (gitignored) -->
  <Import Project="Properties/localSettings.props"
          Condition="Exists('Properties/localSettings.props')" />

</Project>
'@

$Script:TplCommonBuildTargets = @'
<Project>
  <!--
    Common.Build.targets - shared MSBuild logic for every <ModName>_<vsver>.csproj.

    Each .csproj defines, before importing this file:
      $(VSVersion)       e.g. 1.21 or 1.21.5
      $(TargetFramework) e.g. net8.0
      $(GameDirectory)   resolved via localSettings.props or environment vars
      <Dependencies>     items with Version metadata, written into modinfo.json
  -->

  <PropertyGroup>
    <OutputDir>bin/$(Configuration)/$(VSVersion)/Mods</OutputDir>
    <OutputPath>$(OutputDir)/$(ModId)</OutputPath>
    <AssemblyName>$(MSBuildProjectName)</AssemblyName>
    <RootNamespace>__MODNAME__</RootNamespace>
    <!--
      VSMajorMinor lets deps/ folders named by major.minor (somedep-1.21/) resolve
      even when building against a patch version (VSVersion=1.21.5).
    -->
    <VSMajorMinor>$([System.Text.RegularExpressions.Regex]::Match($(VSVersion), '^\d+\.\d+').Value)</VSMajorMinor>
  </PropertyGroup>

  <!-- Game assembly references -->
  <ItemGroup>
    <Reference Include="VintagestoryAPI" HintPath="$(GameDirectory)/VintagestoryAPI.dll"     Private="false" />
    <Reference Include="VintagestoryLib" HintPath="$(GameDirectory)/VintagestoryLib.dll"     Private="false" />
    <Reference Include="VSSurvivalMod"   HintPath="$(GameDirectory)/Mods/VSSurvivalMod.dll"  Private="false" />
    <Reference Include="VSEssentials"    HintPath="$(GameDirectory)/Mods/VSEssentials.dll"   Private="false" />
    <Reference Include="Newtonsoft.Json" HintPath="$(GameDirectory)/Lib/Newtonsoft.Json.dll" Private="false" />
  </ItemGroup>

  <!--
    Dependency DLL resolution, three tiers:
      1. The game's Mods folder - automatic when the dep is installed with the game.
      2. deps/{name}-{vsver}/  - vendored fallback committed to this repo, so the
         mod still builds on a machine without that dep installed.
      3. external/             - ad-hoc one-off DLLs.
  -->
  <ItemGroup>
    <Reference Include="$(GameDirectory)/Mods/*.dll" Private="false"
               Condition="Exists('$(GameDirectory)/Mods')" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="$(ProjectDir)/deps/*-$(VSVersion)/*.dll" Private="false"
               Condition="Exists('$(ProjectDir)/deps')" />
    <Reference Include="$(ProjectDir)/deps/*-$(VSMajorMinor)/*.dll" Private="false"
               Condition="Exists('$(ProjectDir)/deps') and '$(VSMajorMinor)' != '$(VSVersion)'" />
  </ItemGroup>
  <ItemGroup>
    <Reference Include="$(ExternalLibDir)/**/*.dll" Private="false"
               Condition="Exists('$(ExternalLibDir)')" />
  </ItemGroup>

  <!-- Generate modinfo.json from Directory.Build.props -->
  <Target Name="GenerateModInfo" BeforeTargets="Build">
    <PropertyGroup>
      <_ModInfoContent>{
  "type": "$(ModType)",
  "name": "$(ModName)",
  "modid": "$(ModId)",
  "version": "$(ModVersion)",
  "description": "$(Description)",
  "authors": [ @(ModInfoAuthors->'&quot;%(Identity)&quot;', ', ') ],
  "dependencies": { @(Dependencies->'&quot;%(Identity)&quot;: &quot;%(Version)&quot;', ', ') },
  "side": "$(Side)",
  "requiredOnClient": $(RequiredOnClient),
  "requiredOnServer": $(RequiredOnServer)
}</_ModInfoContent>
    </PropertyGroup>
    <MakeDir Directories="$(OutputPath)" />
    <WriteLinesToFile File="$(OutputPath)/modinfo.json"
                      Lines="$(_ModInfoContent)"
                      Overwrite="true"
                      WriteOnlyWhenDifferent="true" />
  </Target>

  <!--
    Symlink resources/assets into the build output so asset edits (JSON, textures,
    sounds) show up in game without a rebuild. Only C# changes need recompiling.
  -->
  <Target Name="LinkAssets" AfterTargets="GenerateModInfo" BeforeTargets="Build">
    <RemoveDir Directories="$(OutputPath)/assets" />
    <Exec Condition="'$(OS)' == 'Windows_NT'"
          Command="mklink /D &quot;$(OutputPath)\assets&quot; &quot;$(AssetsDir)&quot;" />
    <Exec Condition="'$(OS)' != 'Windows_NT'"
          Command="ln -sf &quot;$(AssetsDir)&quot; &quot;$(OutputPath)/assets&quot;" />
  </Target>

  <!-- Optional 32x32 resources/modicon.png is copied to the output root -->
  <Target Name="CopyModIcon" AfterTargets="LinkAssets" BeforeTargets="Build">
    <Copy SourceFiles="$(ProjectDir)/resources/modicon.png"
          DestinationFolder="$(OutputPath)"
          Condition="Exists('$(ProjectDir)/resources/modicon.png')"
          SkipUnchangedFiles="true" />
  </Target>

  <!--
    Files that must never reach the mod portal. Append your own with:
      <PackageExcludes>$(PackageExcludes);$(AssetsDir)/**/*.aseprite</PackageExcludes>
  -->
  <PropertyGroup>
    <PackageExcludes>
      $(AssetsDir)/**/.gitkeep;
      $(AssetsDir)/**/.gitignore;
      $(AssetsDir)/**/.gitattributes;
      $(AssetsDir)/**/Thumbs.db;
      $(AssetsDir)/**/.DS_Store;
      $(AssetsDir)/**/desktop.ini;
      $(AssetsDir)/**/*.bak;
      $(AssetsDir)/**/*.blend;
      $(AssetsDir)/**/*.blend1;
      $(AssetsDir)/**/*.xcf;
      $(AssetsDir)/**/*.psd
    </PackageExcludes>
  </PropertyGroup>

  <!--
    Release only: package Releases/{modid}_{modver}_vs{vsver}.zip

    Files are staged rather than zipping $(OutputPath) directly. That folder's
    assets/ is a symlink back into the source tree, so archiving it sweeps in
    every .gitkeep and every empty scaffold directory. Copying named files into
    a staging folder avoids that, and because MSBuild creates a directory only
    when a file actually lands in it, empty directories disappear by themselves.
  -->
  <Target Name="ZipRelease" AfterTargets="Build" Condition="'$(Configuration)' == 'Release'">
    <PropertyGroup>
      <StageDir>$(ProjectDir)/obj/release-stage/$(VSVersion)/$(ModId)</StageDir>
      <ReleaseZip>$(ProjectDir)/Releases/$(ModId)_$(ModVersion)_vs$(VSVersion).zip</ReleaseZip>
    </PropertyGroup>

    <ItemGroup>
      <PackAsset  Include="$(AssetsDir)/**/*" Exclude="$(PackageExcludes)" />
      <PackBinary Include="$(OutputPath)/*.dll" />
      <PackRoot   Include="$(OutputPath)/modinfo.json" />
      <PackRoot   Include="$(ProjectDir)/resources/modicon.png"
                  Condition="Exists('$(ProjectDir)/resources/modicon.png')" />
    </ItemGroup>

    <RemoveDir Directories="$(StageDir)" />
    <MakeDir Directories="$(StageDir)" />

    <Copy SourceFiles="@(PackAsset)"
          DestinationFiles="@(PackAsset->'$(StageDir)/assets/%(RecursiveDir)%(Filename)%(Extension)')" />
    <Copy SourceFiles="@(PackBinary);@(PackRoot)" DestinationFolder="$(StageDir)" />

    <MakeDir Directories="$(ProjectDir)/Releases" />
    <Delete Files="$(ReleaseZip)" />
    <!-- ZipDirectory is built into MSBuild: no powershell or zip binary needed -->
    <ZipDirectory SourceDirectory="$(StageDir)" DestinationFile="$(ReleaseZip)" />
    <RemoveDir Directories="$(StageDir)" />

    <Message Importance="high" Text="Packaged $(ReleaseZip) (@(PackAsset->Count()) asset files)" />
  </Target>

</Project>
'@

$Script:TplLocalSettings = @'
<Project>
  <!--
    localSettings.props - machine-specific paths. NOT committed.
    Copy to Properties/localSettings.props and fill in your own paths.

    GameDirectory priority (first non-empty wins):
      1. GameDirectory_X_XX below
      2. VINTAGE_STORY_X_XX environment variable
      3. VINTAGE_STORY environment variable

    To support another game version:
      1. Add a GameDirectory_X_XX entry here.
      2. Copy __CSPROJ__ and update VSVersion + TargetFramework.
  -->
  <PropertyGroup>
    <!-- Vintage Story __VSVER__ -->
    <GameDirectory___VSKEY__>__GAMEDIR__</GameDirectory___VSKEY__>
  </PropertyGroup>
</Project>
'@

$Script:TplCsproj = @'
<Project Sdk="Microsoft.NET.Sdk">
  <!--
    __MODNAME__ - Vintage Story __VSVER__ build.
      dotnet build __CSPROJ__
      dotnet build __CSPROJ__ -c Release   (also writes Releases/*.zip)
  -->

  <PropertyGroup>
    <VSVersion>__VSVER__</VSVersion>
    <TargetFramework>__DOTNET__</TargetFramework>
  </PropertyGroup>

  <!-- Written into the generated modinfo.json -->
  <ItemGroup>
    <Dependencies Include="game" Version="&gt;=__GAMEVER__" />
    <!-- Add more: <Dependencies Include="somedep" Version="&gt;=1.0.0" /> -->
  </ItemGroup>

  <!--
    Game path resolution, first non-empty wins:
      1. GameDirectory___VSKEY__ from Properties/localSettings.props
      2. VINTAGE_STORY___VSKEY__ environment variable
      3. VINTAGE_STORY environment variable
  -->
  <PropertyGroup>
    <GameDirectory Condition="'$(GameDirectory___VSKEY__)' != ''">$(GameDirectory___VSKEY__)</GameDirectory>
    <GameDirectory Condition="'$(GameDirectory)' == '' and '$(VINTAGE_STORY___VSKEY__)' != ''">$(VINTAGE_STORY___VSKEY__)</GameDirectory>
    <GameDirectory Condition="'$(GameDirectory)' == ''">$(VINTAGE_STORY)</GameDirectory>
  </PropertyGroup>

  <Import Project="Common.Build.targets" />

</Project>
'@

$Script:TplModSystem = @'
using Vintagestory.API.Common;

[assembly: ModInfo("__MODNAME__", "__MODID__")]

namespace __MODNAME__;

public class __MODNAME__ModSystem : ModSystem
{
    public override void Start(ICoreAPI api)
    {
        base.Start(api);
        api.Logger.Debug("[__MODNAME__] Mod loaded.");
    }

    public override void StartClientSide(ICoreClientAPI api)
    {
    }

    public override void StartServerSide(ICoreServerAPI api)
    {
    }
}
'@

$Script:TplModReadme = @'
# __MODNAME__

A Vintage Story mod.

## Building

Requires the .NET SDK and a Vintage Story install.

1. Copy `Properties/localSettings.props.template` to `Properties/localSettings.props`
   and set your game install path.
2. Build:

```
dotnet build __CSPROJ__                # debug
dotnet build __CSPROJ__ -c Release     # release + zip
```

Debug output lands in `bin/Debug/__VSVER__/Mods/__MODID__/`. Add the `Mods/` folder
above it to the game's ModPaths for live asset reloading.

Release output lands in `Releases/__MODID___<version>_vs__VSVER__.zip`, ready for
the mod portal.

## Layout

| Path | Contents |
|---|---|
| `source/` | C# source |
| `resources/assets/__MODID__/` | Block, item, entity, recipe and lang JSON, textures, shapes, sounds |
| `Directory.Build.props` | Mod identity - name, id, version, description, side, authors |
| `Common.Build.targets` | Shared build logic |
| `deps/` | Vendored dependency DLLs, per game version |
| `external/` | Ad-hoc DLLs, auto-referenced |

`modinfo.json` is generated by the build from `Directory.Build.props`. Do not
create one by hand.

## Licence

Add your licence here.
'@

# Replaces the __TOKEN__ placeholders in a template.
function Expand-Template {
    param([string]$Text, [hashtable]$Tokens)
    foreach ($k in $Tokens.Keys) {
        $Text = $Text.Replace("__${k}__", [string]$Tokens[$k])
    }
    return $Text
}

$Script:AssetSubDirs = @(
    "blocktypes", "itemtypes", "entities", "recipes", "worldgen", "config", "patches",
    "textures/block", "textures/item", "textures/entity", "textures/gui",
    "shapes/block", "shapes/item", "shapes/entity",
    "sounds", "music"
)

# ─── Mod repo git init ────────────────────────────────────────────────────────
# The scaffolded mod folder is a self-contained git repo from the first minute.
# No remote is configured: copy the folder out and push it by hand.
function Initialize-ModRepo {
    param([string]$ModDir, [string]$Message)

    if (Test-Path (Join-Path $ModDir ".git")) {
        Write-Info "Already a git repo - leaving history alone."
        return $true
    }

    git -C $ModDir init --quiet 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "git init failed - the mod folder is fine, just not a repo yet."
        return $false
    }

    # Normalise the default branch name across git versions.
    git -C $ModDir symbolic-ref HEAD refs/heads/main 2>&1 | Out-Null

    git -C $ModDir add -A 2>&1 | Out-Null
    $commitOut = (git -C $ModDir commit -m $Message 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "Files staged but the initial commit failed."
        if ($commitOut -match 'user\.(email|name)|tell me who you are') {
            Write-Info "Set your git identity, then commit:"
            Write-Info "  git config --global user.name  ""Your Name"""
            Write-Info "  git config --global user.email ""you@example.com"""
            Write-Info "  git -C ""$ModDir"" commit -m ""$Message"""
        }
        return $false
    }

    Write-Success "Initialised git repo on branch 'main' with an initial commit."
    return $true
}

# ─── new ──────────────────────────────────────────────────────────────────────
function Invoke-New {
    param([string]$Name)
    if (-not $Name) {
        Write-Err "Usage: new <ModName>    (PascalCase, e.g. GlowingMushroom)"
        exit 1
    }
    if ($Name -notmatch '^[A-Za-z][A-Za-z0-9]*$') {
        Write-Err "Mod name must be alphanumeric and start with a letter: '$Name'"
        Write-Info "This becomes the C# namespace, so no spaces, dots or dashes."
        exit 1
    }
    if (Test-WorkspaceExists $Name) {
        Write-Err "A workspace named '$Name' already exists."
        Write-Info "Switch to it:  .\scripts\vsmod.ps1 use $Name"
        exit 1
    }

    $h       = Get-Harness
    $modId   = $Name.ToLower() -replace '[^a-z0-9]', ''
    $vsVer   = Get-DefaultsValue 'apiVersion'   '1.21.5'
    $dotnet  = Get-DefaultsValue 'dotnetTarget' 'net8.0'
    $gameVer = Get-DefaultsValue 'gameVersion'  '1.21.0'
    $author  = Coalesce (Get-Prop $h 'author') 'Author'
    $gameDir = Coalesce (Get-Prop $h 'gameDirectory') 'C:\Program Files\Vintagestory'
    $vsKey   = $vsVer -replace '\.', '_'

    $wsDir  = Get-WorkspaceDir $Name
    $modDir = Join-Path $wsDir "mod"

    Write-Header "Creating workspace: $Name"

    $tokens = @{
        MODNAME = $Name; MODID = $modId; VSVER = $vsVer; VSKEY = $vsKey
        DOTNET  = $dotnet; GAMEVER = $gameVer; GAMEDIR = $gameDir; AUTHOR = $author
        CSPROJ  = "${Name}_${vsVer}.csproj"
    }

    # ── Directories ───────────────────────────────────────────────────────────
    foreach ($d in @("source", "Properties", "deps", "external")) {
        New-Item -ItemType Directory -Path (Join-Path $modDir $d) -Force | Out-Null
    }
    foreach ($d in $Script:AssetSubDirs) {
        $p = Join-Path $modDir "resources/assets/$modId/$d"
        New-Item -ItemType Directory -Path $p -Force | Out-Null
        "" | Set-Content (Join-Path $p ".gitkeep") -Encoding UTF8
    }
    New-Item -ItemType Directory -Path (Join-Path $modDir "resources/assets/$modId/lang") -Force | Out-Null
    foreach ($d in @("deps", "external")) {
        "" | Set-Content (Join-Path (Join-Path $modDir $d) ".gitkeep") -Encoding UTF8
    }

    # ── Files ─────────────────────────────────────────────────────────────────
    $Script:TplGitignore | Set-Content (Join-Path $modDir ".gitignore") -Encoding UTF8
    (Expand-Template $Script:TplDirectoryBuildProps  $tokens) | Set-Content (Join-Path $modDir "Directory.Build.props") -Encoding UTF8
    (Expand-Template $Script:TplCommonBuildTargets   $tokens) | Set-Content (Join-Path $modDir "Common.Build.targets") -Encoding UTF8
    (Expand-Template $Script:TplCsproj               $tokens) | Set-Content (Join-Path $modDir "${Name}_${vsVer}.csproj") -Encoding UTF8
    (Expand-Template $Script:TplModSystem            $tokens) | Set-Content (Join-Path $modDir "source/${Name}ModSystem.cs") -Encoding UTF8
    (Expand-Template $Script:TplModReadme            $tokens) | Set-Content (Join-Path $modDir "README.md") -Encoding UTF8
    (Expand-Template $Script:TplLocalSettings        $tokens) | Set-Content (Join-Path $modDir "Properties/localSettings.props.template") -Encoding UTF8
    Copy-Item (Join-Path $modDir "Properties/localSettings.props.template") (Join-Path $modDir "Properties/localSettings.props")
    "{}" | Set-Content (Join-Path $modDir "resources/assets/$modId/lang/en.json") -Encoding UTF8

    # ── workspace.json ────────────────────────────────────────────────────────
    $ws = [PSCustomObject]@{
        modName       = $Name
        modId         = $modId
        modVersion    = "1.0.0"
        gameVersion   = $gameVer
        apiVersion    = $vsVer
        dotnetTarget  = $dotnet
        gameDirectory = ""
        dependencies  = @()
        examples      = @()
        gamesrc       = @()
        notes         = "Per-mod settings. gameDirectory empty means inherit from harness.json."
    }
    Save-Json $ws (Join-Path $wsDir "workspace.json")

    # ── git repo ──────────────────────────────────────────────────────────────
    Write-Host ""
    Initialize-ModRepo $modDir "Initial commit: $Name v1.0.0 scaffold" | Out-Null

    # ── activate + link ───────────────────────────────────────────────────────
    $h.activeWorkspace = $Name
    Save-Harness $h
    $wsLoaded = Get-Workspace $Name
    Sync-WorkspaceLinks $wsLoaded | Out-Null

    Write-Host ""
    Write-Success "Workspace '$Name' created and made active."
    Write-Host ""
    Write-Host "  workspaces\$Name\" -ForegroundColor White
    Write-Host "    mod\             " -NoNewline -ForegroundColor Cyan; Write-Host "standalone git repo - this is what you copy out and push"
    Write-Host "    workspace.json   " -NoNewline -ForegroundColor Cyan; Write-Host "this mod's settings"
    Write-Host "    api\ gamesrc\    " -NoNewline -ForegroundColor Cyan; Write-Host "links into the shared cache"
    Write-Host ""
    Write-Host "  Next:" -ForegroundColor White
    Write-Host "    1. Check workspaces\$Name\mod\Properties\localSettings.props has your game path"
    Write-Host "    2. Open your agent in the harness root and describe what the mod should do"
    Write-Host "    3. .\scripts\vsmod.ps1 build"
    Write-Host ""
}

# ─── import ───────────────────────────────────────────────────────────────────
# Deliberately mirrors 'new': same workspace shape, same links, same result.
# The only difference is where the mod/ contents come from.
function Invoke-Import {
    param([string]$Source, [string]$Name = "")

    if (-not $Source) {
        Write-Err "Usage: import <source> [Name]"
        Write-Host ""
        Write-Host "  source can be:" -ForegroundColor Cyan
        Write-Host "    a git URL        https://github.com/someone/TheirMod.git"
        Write-Host "    a local folder   C:\dev\MyOldMod"
        Write-Host "    a .zip file      C:\downloads\SomeMod.zip"
        Write-Host ""
        Write-Host "  Git history is preserved when there is any, so a fork stays a fork."
        exit 1
    }

    # ── Work out the workspace name ───────────────────────────────────────────
    if (-not $Name) {
        $base = $Source.TrimEnd("/\")
        $base = [System.IO.Path]::GetFileName($base)
        $base = $base -replace '\.git$', ''
        $base = $base -replace '\.zip$', ''
        $base = $base -replace '-(main|master|src|source)$', ''
        $Name = ($base -replace '[^A-Za-z0-9]', '')
    }
    if (-not $Name) { Write-Err "Could not derive a name from '$Source'. Pass one: import <source> <Name>"; exit 1 }

    if (Test-WorkspaceExists $Name) {
        Write-Err "A workspace named '$Name' already exists."
        Write-Info "Switch to it:   .\scripts\vsmod.ps1 use $Name"
        Write-Info "Or import as:   .\scripts\vsmod.ps1 import $Source <OtherName>"
        exit 1
    }

    $wsDir  = Get-WorkspaceDir $Name
    $modDir = Join-Path $wsDir "mod"

    Write-Header "Importing: $Name"

    # ── Acquire the source ────────────────────────────────────────────────────
    New-Item -ItemType Directory -Path $wsDir -Force | Out-Null

    try {
        if ($Source -match "^https?://" -or $Source -match "^git@") {
            Write-Info "Cloning $Source"
            # Full clone, not shallow: this is your working repo now, and a
            # shallow clone would cripple later history work.
            git clone $Source $modDir
            if ($LASTEXITCODE -ne 0) { throw "git clone failed." }

        } elseif ($Source -match "\.zip$") {
            if (-not (Test-Path $Source)) { throw "Zip not found: $Source" }
            Write-Info "Extracting $Source"
            $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "vsmod_import_$([guid]::NewGuid().ToString('N'))"
            Expand-Archive -Path $Source -DestinationPath $tmp
            # GitHub zips wrap everything in one folder - unwrap it.
            $children = @(Get-ChildItem $tmp)
            if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
                Move-Item $children[0].FullName $modDir
            } else {
                Move-Item $tmp $modDir
            }
            Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

        } elseif (Test-Path $Source) {
            Write-Info "Copying $Source"
            Copy-Item -Recurse $Source $modDir

        } else {
            throw "Source not found and not a URL: $Source"
        }
    } catch {
        Remove-Item $wsDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Err $_.Exception.Message
        exit 1
    }

    # ── Inspect what arrived ──────────────────────────────────────────────────
    Write-Host ""
    Write-Header "Inspecting"

    $h       = Get-Harness
    $modId   = $Name.ToLower() -replace '[^a-z0-9]', ''
    $modVer  = "1.0.0"
    $modName = $Name
    $gameVer = Get-DefaultsValue 'gameVersion' '1.21.0'
    $apiVer  = Get-DefaultsValue 'apiVersion'  '1.21.5'
    $dotnet  = Get-DefaultsValue 'dotnetTarget' 'net8.0'

    # modinfo.json - static file in older/foreign mods
    $mi = Join-Path $modDir "modinfo.json"
    if (Test-Path $mi) {
        try {
            $obj = Get-Content $mi -Raw | ConvertFrom-Json
            if (Get-Prop $obj 'modid')   { $modId   = (Get-Prop $obj 'modid') }
            if (Get-Prop $obj 'name')    { $modName = (Get-Prop $obj 'name') }
            if (Get-Prop $obj 'version') { $modVer  = (Get-Prop $obj 'version') }
            Write-Success "modinfo.json    modid=$modId  version=$modVer"
            $deps = Get-Prop $obj 'dependencies'
            if ($deps) {
                $gameDep = Get-Prop $deps 'game'
                if ($gameDep -and $gameDep -match '(\d+\.\d+(\.\d+)?)') { $gameVer = $Matches[1] }
            }
        } catch { Write-Warn "modinfo.json present but unparseable." }
    }

    # Directory.Build.props - workspace-native mods
    $dbp = Join-Path $modDir "Directory.Build.props"
    if (Test-Path $dbp) {
        $m = Select-String -Path $dbp -Pattern '<ModVersion>(.*?)</ModVersion>' -ErrorAction SilentlyContinue
        if ($m) { $modVer = $m.Matches[0].Groups[1].Value.Trim() }
        $m = Select-String -Path $dbp -Pattern '<ModId>(.*?)</ModId>' -ErrorAction SilentlyContinue
        if ($m) { $modId = $m.Matches[0].Groups[1].Value.Trim() }
        $m = Select-String -Path $dbp -Pattern '<ModName>(.*?)</ModName>' -ErrorAction SilentlyContinue
        if ($m) { $modName = $m.Matches[0].Groups[1].Value.Trim() }
    }

    # csproj files - the name usually encodes the target game version
    $verFromNameFound = $false
    $csprojs = @(Get-ChildItem $modDir -Filter "*.csproj" -File -ErrorAction SilentlyContinue)
    if ($csprojs.Count -gt 0) {
        foreach ($c in $csprojs) { Write-Success "csproj          $($c.Name)" }
        $verFromName = $csprojs |
            ForEach-Object { if ($_.BaseName -match '_(\d+\.\d+(\.\d+)?)$') { $Matches[1] } } |
            Sort-Object -Descending | Select-Object -First 1
        if ($verFromName) { $apiVer = $verFromName; $verFromNameFound = $true }
        $tfm = $csprojs | ForEach-Object {
            $t = Select-String -Path $_.FullName -Pattern '<TargetFramework>(.*?)</TargetFramework>' -ErrorAction SilentlyContinue
            if ($t) { $t.Matches[0].Groups[1].Value.Trim() }
        } | Select-Object -First 1
        if ($tfm) { $dotnet = $tfm }
    } else {
        Write-Warn "No .csproj found - assets-only mod, or the project file is missing."
    }

    # If no csproj encoded a version, the mod's declared game version is a far
    # better guess for which API source to read than the harness default.
    if (-not $verFromNameFound -and $gameVer) { $apiVer = $gameVer }

    $hasDbp = Test-Path $dbp
    $hasCbt = Test-Path (Join-Path $modDir "Common.Build.targets")
    if ($hasDbp -and $hasCbt) {
        Write-Success "Build system    workspace-native"
    } else {
        Write-Warn "Build system    foreign / legacy"
        Write-Info "Ask your agent to migrate it, or leave it and build as-is."
    }

    $srcLayout = if (Test-Path (Join-Path $modDir "source")) { "source/" }
                 elseif (Test-Path (Join-Path $modDir "src")) { "src/" }
                 else { "(none)" }
    $assetLayout = if (Test-Path (Join-Path $modDir "resources/assets")) { "resources/assets/" }
                   elseif (Test-Path (Join-Path $modDir "assets")) { "assets/" }
                   else { "(none)" }
    Write-Info "Source layout   $srcLayout"
    Write-Info "Asset layout    $assetLayout"
    Write-Info "Game version    $gameVer      API context: $apiVer      TFM: $dotnet"

    # ── Make sure it is a proper repo ─────────────────────────────────────────
    Write-Host ""
    if (Test-Path (Join-Path $modDir ".git")) {
        $branch = (git -C $modDir rev-parse --abbrev-ref HEAD 2>&1)
        Write-Success "Existing git history preserved (branch: $branch)."
        $origin = (git -C $modDir remote get-url origin 2>&1)
        if ($LASTEXITCODE -eq 0 -and $origin) {
            Write-Info "Remote 'origin' points at: $origin"
            Write-Info "This harness never pushes. Copy the repo out and push it yourself."
        }
    } else {
        if (-not (Test-Path (Join-Path $modDir ".gitignore"))) {
            $Script:TplGitignore | Set-Content (Join-Path $modDir ".gitignore") -Encoding UTF8
            Write-Info "Added a .gitignore (build output, localSettings.props, editor noise)."
        }
        Initialize-ModRepo $modDir "Import $modName v$modVer" | Out-Null
    }

    # ── workspace.json ────────────────────────────────────────────────────────
    $ws = [PSCustomObject]@{
        modName       = $modName
        modId         = $modId
        modVersion    = $modVer
        gameVersion   = $gameVer
        apiVersion    = $apiVer
        dotnetTarget  = $dotnet
        gameDirectory = ""
        dependencies  = @()
        examples      = @()
        gamesrc       = @()
        notes         = "Imported from: $Source"
    }
    Save-Json $ws (Join-Path $wsDir "workspace.json")

    $h.activeWorkspace = $Name
    Save-Harness $h
    Sync-WorkspaceLinks (Get-Workspace $Name) | Out-Null

    Write-Host ""
    Write-Success "Workspace '$Name' created and made active."
    if (-not (Test-Path (Get-CachePath "api" $apiVer))) {
        Write-Info "For API context, run: .\scripts\vsmod.ps1 fetch-api $apiVer"
    }
    Write-Info "Then open your agent and describe what to change, add or fix."
    Write-Host ""
}

# ─── git-init (for an imported folder that was never a repo) ──────────────────
function Invoke-GitInit {
    $ws     = Get-Workspace
    $modDir = Get-ModDir $ws
    $name   = Coalesce (Get-Prop $ws 'modName') (Split-Path $ws._dir -Leaf)
    $ver    = Coalesce (Get-Prop $ws 'modVersion') '1.0.0'

    Write-Header "Preparing git repo: workspaces\$(Split-Path $ws._dir -Leaf)\mod"
    if (-not (Test-Path (Join-Path $modDir ".gitignore"))) {
        $Script:TplGitignore | Set-Content (Join-Path $modDir ".gitignore") -Encoding UTF8
        Write-Info "Added .gitignore"
    }
    Initialize-ModRepo $modDir "Initial commit: $name v$ver" | Out-Null
}

# ─── export (copy out, never push) ────────────────────────────────────────────
function Invoke-Export {
    param([string]$Destination = "")

    $ws     = Get-Workspace
    $wsName = Split-Path $ws._dir -Leaf
    $modDir = Get-ModDir $ws

    if (-not (Test-Path $modDir)) { Write-Err "No mod folder at workspaces\$wsName\mod"; exit 1 }

    if (-not $Destination) {
        $exportRoot = Get-Prop (Get-Harness) 'exportDirectory'
        if (-not $exportRoot) { $exportRoot = Join-Path $Root "exports" }
        $exportRoot = [System.Environment]::ExpandEnvironmentVariables($exportRoot)
        $Destination = Join-Path $exportRoot $wsName
    }

    if (Test-Path $Destination) {
        Write-Err "Destination already exists: $Destination"
        Write-Info "Delete it or pass another path: export <path>"
        exit 1
    }

    Write-Header "Exporting $wsName"

    $dirty = @(git -C $modDir status --porcelain 2>&1 | Where-Object { $_ })
    if ($dirty.Count -gt 0) {
        Write-Warn "$($dirty.Count) uncommitted change(s) in the mod repo."
        Write-Info "Commit them first if you want them in the exported history:"
        Write-Info "  git -C ""$modDir"" add -A"
        Write-Info "  git -C ""$modDir"" commit -m ""..."""
        Write-Host ""
    }

    $parent = Split-Path $Destination -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    # Copy everything including .git, but not build output.
    Copy-Item -Recurse $modDir $Destination
    foreach ($junk in @("bin", "obj", "Releases", "Properties/localSettings.props")) {
        $p = Join-Path $Destination $junk
        if (Test-Path $p) { Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Write-Success "Copied to: $Destination"
    Write-Host ""
    Write-Info "It is a complete git repo. To publish it yourself:"
    Write-Host "    cd ""$Destination""" -ForegroundColor Cyan
    Write-Host "    git remote add origin <your-repo-url>" -ForegroundColor Cyan
    Write-Host "    git push -u origin main" -ForegroundColor Cyan
    Write-Host ""
}

# ─── API / gamesrc / deps / examples ──────────────────────────────────────────
function Invoke-FetchApi {
    param([string]$Version)
    if (-not $Version) {
        $ws = Get-Workspace
        $Version = Get-Prop $ws 'apiVersion'
        if (-not $Version) { Write-Err "Usage: fetch-api <version>   (e.g. 1.21.5)"; exit 1 }
        Write-Info "No version given - using the active workspace's apiVersion: $Version"
    }
    $Version = $Version.TrimStart("v")

    Write-Header "Fetching vsapi $Version"
    $path = Get-CachedApi $Version
    if (-not $path) { exit 1 }
    Write-Success "Cached at: cache/api/$Version"

    $dir = Get-ActiveWorkspaceDir -Quiet
    if ($dir) {
        $ws = Get-Workspace
        $ws.apiVersion = $Version
        Save-Workspace $ws
        Sync-WorkspaceLinks $ws -Quiet | Out-Null
        Write-Success "Linked into the active workspace and set as its apiVersion."
    } else {
        Write-Info "No active workspace - cached only. It will link in on the next 'use'."
    }
}

function Invoke-UseApi {
    param([string]$Version)
    if (-not $Version) { Write-Err "Usage: use-api <version>"; exit 1 }
    $Version = $Version.TrimStart("v")

    if (-not (Test-Path (Get-CachePath "api" $Version))) {
        Write-Warn "vsapi $Version is not cached yet - fetching it now."
        if (-not (Get-CachedApi $Version)) { exit 1 }
    }
    $ws = Get-Workspace
    $ws.apiVersion = $Version
    Save-Workspace $ws
    Sync-WorkspaceLinks $ws | Out-Null
    Write-Success "Active workspace now reads API $Version."
}

function Invoke-ListApi {
    Write-Header "Cached API versions"
    $apiDir = Join-Path $CacheDir "api"
    $dirs = @(Get-ChildItem $apiDir -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) { Write-Warn "None. Run: fetch-api <version>"; return }

    $active = ""
    $wsDir = Get-ActiveWorkspaceDir -Quiet
    if ($wsDir) { $active = Get-Prop (Get-Workspace) 'apiVersion' }

    foreach ($d in $dirs) {
        if ($d.Name -eq $active) { Write-Host "  * $($d.Name)  (used by the active workspace)" -ForegroundColor Green }
        else { Write-Host "  o $($d.Name)" }
    }
    Write-Host ""
    Write-Info "Cached once, shared by every workspace."
}

function Invoke-FetchGameSrc {
    param([string]$Name, [string]$Version = "")
    if (-not $Name) {
        Write-Err "Usage: fetch-gamesrc <name> [version]"
        Write-Host "  Known: $($Script:KnownGameSrcRepos.Keys -join ', ')"
        exit 1
    }
    Write-Header "Fetching game source: $Name"
    $path = Get-CachedGameSrc $Name $Version
    if (-not $path) { exit 1 }

    $key = Split-Path $path -Leaf
    Write-Success "Cached at: cache/gamesrc/$key"

    $dir = Get-ActiveWorkspaceDir -Quiet
    if ($dir) {
        $ws   = Get-Workspace
        $list = New-Object 'System.Collections.Generic.List[string]'
        foreach ($i in (Get-PropArray $ws 'gamesrc')) { $list.Add($i) }
        if (-not $list.Contains($key)) { $list.Add($key) }
        $ws.gamesrc = $list.ToArray()
        Save-Workspace $ws
        Sync-WorkspaceLinks $ws -Quiet | Out-Null
        Write-Success "Linked into the active workspace."
    }
}

function Invoke-ListGameSrc {
    Write-Header "Cached game source repos"
    $d = Join-Path $CacheDir "gamesrc"
    $dirs = @(Get-ChildItem $d -Directory -ErrorAction SilentlyContinue)
    if ($dirs.Count -eq 0) {
        Write-Warn "None cached."
        Write-Info "Run: fetch-gamesrc essentials   or   fetch-gamesrc survival"
    } else {
        foreach ($g in $dirs) {
            $line = git -C $g.FullName log --oneline -1 2>$null
            Write-Host "  v $($g.Name)" -ForegroundColor Green -NoNewline
            if ($line) { Write-Host "   ($line)" } else { Write-Host "" }
        }
    }
    Write-Host ""
    Write-Host "  Available:" -ForegroundColor Cyan
    foreach ($k in $Script:KnownGameSrcRepos.Keys) { Write-Host "    o $k" }
}

# Adds a dependency or example to the cache, then links it into this workspace.
function Add-Context {
    param([string]$Kind, [string]$Source, [string]$Name)

    if (-not $Source) {
        $verb = if ($Kind -eq 'dependencies') { 'add-dep' } else { 'add-example' }
        Write-Err "Usage: $verb <path-or-url> [name]"
        exit 1
    }
    if (-not $Name) {
        $Name = [System.IO.Path]::GetFileName($Source.TrimEnd("/\")) -replace '\.git$', ''
    }

    $ws = Get-Workspace
    if (-not (Get-CachedContext $Kind $Name $Source)) { exit 1 }

    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($i in (Get-PropArray $ws $Kind)) { $list.Add($i) }
    if (-not $list.Contains($Name)) { $list.Add($Name) }
    $ws.$Kind = $list.ToArray()
    Save-Workspace $ws
    Sync-WorkspaceLinks $ws -Quiet | Out-Null

    Write-Success "$Name is now in this workspace's $Kind."
    Write-Info "Other workspaces can link the same cached copy with the same command."
}

function Remove-Context {
    param([string]$Kind, [string]$Name)
    if (-not $Name) { Write-Err "Usage: remove-$($Kind -replace 'ies$','y' -replace 's$','') <name>"; exit 1 }

    $ws   = Get-Workspace
    $list = @(Get-PropArray $ws $Kind | Where-Object { $_ -ne $Name })
    $ws.$Kind = $list
    Save-Workspace $ws

    $link = Join-Path (Join-Path $ws._dir $Kind) $Name
    if (Test-DirLink $link) { Remove-DirLink $link }

    Write-Success "Removed '$Name' from this workspace's $Kind."
    Write-Info "The cached copy stays in cache/$Kind/$Name for other workspaces."
}

function Invoke-ListContext {
    param([string]$Kind)
    $ws = Get-Workspace
    Write-Header "$Kind in this workspace"
    $items = @(Get-PropArray $ws $Kind)
    if ($items.Count -eq 0) { Write-Host "  (none)"; return }
    foreach ($i in $items) {
        $p = Join-Path (Join-Path $ws._dir $Kind) $i
        if (Test-Path $p) { Write-Host "  v $i" -ForegroundColor Green }
        else { Write-Host "  x $i  (link missing - run: sync)" -ForegroundColor Red }
    }
}

# ─── add-dep-dll ──────────────────────────────────────────────────────────────
function Invoke-AddDepDll {
    param([string]$DepName, [string]$VsVersion, [string]$DllSource = "")

    if (-not $DepName -or -not $VsVersion) {
        Write-Err "Usage: add-dep-dll <dep-name> <vs-version> [dll-path]"
        Write-Host ""
        Write-Host "    add-dep-dll CarryCapacity 1.21                       " -NoNewline
        Write-Host "searches the game Mods folder" -ForegroundColor DarkGray
        Write-Host "    add-dep-dll CarryCapacity 1.21 C:\path\to\Mod.dll"
        exit 1
    }

    $ws        = Get-Workspace
    $modDir    = Get-ModDir $ws
    $vsVer     = $VsVersion.TrimStart("v")
    $depFolder = Join-Path (Join-Path $modDir "deps") "$DepName-$vsVer"

    $dllPath = $DllSource
    if (-not $dllPath) {
        $gameDir = Resolve-GameDirectory $ws
        if ($gameDir) {
            $gameMods = Join-Path $gameDir "Mods"
            if (Test-Path $gameMods) {
                $found = @(Get-ChildItem $gameMods -ErrorAction SilentlyContinue |
                           Where-Object { $_.Name -like "$DepName*.dll" })
                if ($found.Count -gt 0) {
                    $dllPath = $found[0].FullName
                    Write-Info "Found in the game Mods folder: $($found[0].Name)"
                }
            }
        }
    }

    if (-not $dllPath -or -not (Test-Path $dllPath)) {
        Write-Err "Could not find '$DepName*.dll'."
        Write-Info "Give the path explicitly, or check gameDirectory in harness.json."
        exit 1
    }

    New-Item -ItemType Directory -Path $depFolder -Force | Out-Null
    Copy-Item $dllPath $depFolder -Force

    Write-Success "Copied $([System.IO.Path]::GetFileName($dllPath)) -> mod\deps\$DepName-$vsVer\"
    Write-Info "It is referenced automatically for VS $vsVer builds and travels with the repo."
}

# ─── build ────────────────────────────────────────────────────────────────────
function Invoke-Build {
    param([string]$Mode = "debug")

    $Mode = $Mode.ToLower()
    if ($Mode -notin @("debug", "release")) { Write-Err "Use: build debug   or   build release"; exit 1 }

    $ws     = Get-Workspace
    $wsName = Split-Path $ws._dir -Leaf
    $modDir = Get-ModDir $ws
    $config = if ($Mode -eq "release") { "Release" } else { "Debug" }

    $csprojs = @(Get-ChildItem $modDir -Filter "*.csproj" -File -ErrorAction SilentlyContinue)
    if ($csprojs.Count -eq 0) {
        Write-Err "No .csproj in workspaces\$wsName\mod"
        Write-Info "Assets-only mod? Then there is nothing to compile."
        exit 1
    }

    # Debug builds only the csproj matching the active API version, for speed.
    # Release builds every one, so all supported game versions get a zip.
    $apiVersion = Get-Prop $ws 'apiVersion'
    if ($Mode -eq "debug" -and $apiVersion) {
        $match = @($csprojs | Where-Object { $_.BaseName -like "*_$apiVersion" })
        if ($match.Count -eq 0 -and $apiVersion -match '^(\d+\.\d+)') {
            $mm = $Matches[1]
            $match = @($csprojs | Where-Object { $_.BaseName -like "*_$mm*" })
        }
        if ($match.Count -gt 0) { $csprojs = $match }
    }

    $gameDir = Resolve-GameDirectory $ws
    if ($gameDir -and -not (Test-GameInstall $gameDir)) {
        Write-Warn "VintagestoryAPI.dll not found at: $gameDir"
        Write-Info "Check gameDirectory in harness.json, or the mod's Properties\localSettings.props."
    }

    Write-Header "Building $wsName [$config]"

    $allOk = $true
    foreach ($csproj in $csprojs) {
        Write-Host ""
        Write-Info "Project: $($csproj.Name)"
        dotnet build $csproj.FullName --configuration $config --nologo
        if ($LASTEXITCODE -ne 0) { $allOk = $false; Write-Err "Build failed: $($csproj.Name)"; continue }

        if ($Mode -eq "debug") {
            if ($csproj.BaseName -match '_(\d+\.\d+(\.\d+)?)$') {
                $vsv     = $Matches[1]
                $modsDir = Join-Path (Join-Path (Join-Path (Join-Path $modDir "bin") "Debug") $vsv) "Mods"
                Write-Success "Output -> $modsDir"
            }
        }
    }

    if ($Mode -eq "release") {
        $relDir = Join-Path $modDir "Releases"
        if (Test-Path $relDir) {
            foreach ($z in @(Get-ChildItem $relDir -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 3)) {
                Write-Success "Release -> $($z.FullName)"
            }
        }
    }

    Write-Host ""
    if (-not $allOk) { Write-Err "One or more builds failed."; exit 1 }
    Write-Success "Build complete."

    if ($Mode -eq "debug") {
        Write-Host ""
        Write-Info "Add the Mods\ folder above to the game's ModPaths in clientsettings.json"
        Write-Info "and asset edits go live without rebuilding. C# changes still need a rebuild."
    }
}

# ─── cache ────────────────────────────────────────────────────────────────────
function Invoke-Cache {
    param([string]$Action = "list", [string]$Target = "")

    switch ($Action.ToLower()) {
        "list" {
            Write-Header "Shared cache"
            Write-Info "Downloaded once, linked into every workspace that wants it."
            foreach ($kind in @("api", "gamesrc", "dependencies", "examples")) {
                $d = Join-Path $CacheDir $kind
                $items = @(Get-ChildItem $d -Directory -ErrorAction SilentlyContinue)
                Write-Host ""
                Write-Host "  $kind/" -ForegroundColor Cyan
                if ($items.Count -eq 0) { Write-Host "    (empty)" }
                else { foreach ($i in $items) { Write-Host "    $($i.Name)" } }
            }
            Write-Host ""
        }
        "remove" {
            if (-not $Target) { Write-Err "Usage: cache remove <kind>/<name>   e.g. cache remove api/1.20.0"; exit 1 }
            $parts = $Target -split '[/\\]', 2
            if ($parts.Count -ne 2) { Write-Err "Expected <kind>/<name>."; exit 1 }
            $p = Get-CachePath $parts[0] $parts[1]
            if (-not (Test-Path $p)) { Write-Err "Not cached: $Target"; exit 1 }
            Write-Warn "Workspaces linking this will show a broken link until re-fetched."
            if ((Read-Host "Type YES to remove") -ne "YES") { Write-Info "Cancelled."; return }
            Remove-Item $p -Recurse -Force
            Write-Success "Removed cache/$Target"
        }
        default { Write-Err "Usage: cache [list|remove <kind>/<name>]" }
    }
}

# ─── help ─────────────────────────────────────────────────────────────────────
function Invoke-Help {
    Write-Host ""
    Write-Host "Vintage Story Modding Harness" -ForegroundColor White
    Write-Host "  Each mod gets its own workspace. Downloads are shared. Nothing is ever pushed." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Switching between mods:" -ForegroundColor Cyan
    Write-Host "    use <Name>                   Make a workspace active. This is the one command."
    Write-Host "    list                         List every workspace"
    Write-Host "    status                       Show the active workspace in detail"
    Write-Host "    sync                         Rebuild this workspace's cache links"
    Write-Host "    remove <Name>                Delete a workspace (asks first)"
    Write-Host ""
    Write-Host "  Starting work:" -ForegroundColor Cyan
    Write-Host "    new <ModName>                Scaffold a new mod; mod\ becomes a git repo"
    Write-Host "    import <src> [Name]          Import a folder, .zip or git URL as a workspace"
    Write-Host "    git-init                     Turn an imported mod folder into a git repo"
    Write-Host ""
    Write-Host "  Building:" -ForegroundColor Cyan
    Write-Host "    build [debug|release]        Compile the active mod (default: debug)"
    Write-Host "      debug    -> mod\bin\Debug\<vsver>\Mods\"
    Write-Host "      release  -> mod\Releases\<modid>_<ver>_vs<vsver>.zip"
    Write-Host ""
    Write-Host "  Handing off:" -ForegroundColor Cyan
    Write-Host "    export [path]                Copy the mod repo out, ready for you to push"
    Write-Host ""
    Write-Host "  Reference sources (cached once, shared by all workspaces):" -ForegroundColor Cyan
    Write-Host "    fetch-api <version>          Download vsapi source and link it here"
    Write-Host "    use-api <version>            Point this workspace at another cached version"
    Write-Host "    list-api                     List cached API versions"
    Write-Host "    fetch-gamesrc <name> [ver]   essentials | survival | creative"
    Write-Host "    list-gamesrc                 List cached game source repos"
    Write-Host "    cache [list|remove <kind>/<name>]   Inspect or prune the cache"
    Write-Host ""
    Write-Host "  Per-workspace context:" -ForegroundColor Cyan
    Write-Host "    add-dep <path-or-url> [name]      Dependency mod source, for the agent to read"
    Write-Host "    remove-dep <name>                 Unlink it (cached copy stays)"
    Write-Host "    list-deps                         List dependencies in this workspace"
    Write-Host "    add-example <path-or-url> [name]  Example mod source"
    Write-Host "    remove-example <name>             Unlink it"
    Write-Host "    list-examples                     List examples in this workspace"
    Write-Host "    add-dep-dll <name> <vsver> [dll]  Vendor a dependency DLL into mod\deps\"
    Write-Host ""
    Write-Host "  Setup:" -ForegroundColor Cyan
    Write-Host "    init                         Create cache\ and workspaces\, check config"
    Write-Host ""
}

# ─── Router ───────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "init"           { Invoke-Init }
    "help"           { Invoke-Help }
    "--help"         { Invoke-Help }
    "-h"             { Invoke-Help }

    "use"            { Invoke-Use    (ArgAt $CmdArgs 0 "") }
    "switch"         { Invoke-Use    (ArgAt $CmdArgs 0 "") }
    "list"           { Invoke-List }
    "ls"             { Invoke-List }
    "status"         { Invoke-Status }
    "sync"           { Invoke-Sync }
    "remove"         { Invoke-Remove (ArgAt $CmdArgs 0 "") }

    "new"            { Invoke-New    (ArgAt $CmdArgs 0 "") }
    "new-mod"        { Invoke-New    (ArgAt $CmdArgs 0 "") }
    "import"         { Invoke-Import (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "import-mod"     { Invoke-Import (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "git-init"       { Invoke-GitInit }

    "build"          { Invoke-Build  (ArgAt $CmdArgs 0 "debug") }
    "export"         { Invoke-Export (ArgAt $CmdArgs 0 "") }

    "fetch-api"      { Invoke-FetchApi     (ArgAt $CmdArgs 0 "") }
    "use-api"        { Invoke-UseApi       (ArgAt $CmdArgs 0 "") }
    "list-api"       { Invoke-ListApi }
    "fetch-gamesrc"  { Invoke-FetchGameSrc (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "list-gamesrc"   { Invoke-ListGameSrc }
    "cache"          { Invoke-Cache        (ArgAt $CmdArgs 0 "list") (ArgAt $CmdArgs 1 "") }

    "add-dep"        { Add-Context    "dependencies" (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "remove-dep"     { Remove-Context "dependencies" (ArgAt $CmdArgs 0 "") }
    "list-deps"      { Invoke-ListContext "dependencies" }
    "add-example"    { Add-Context    "examples" (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "remove-example" { Remove-Context "examples" (ArgAt $CmdArgs 0 "") }
    "list-examples"  { Invoke-ListContext "examples" }
    "add-dep-dll"    { Invoke-AddDepDll (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") (ArgAt $CmdArgs 2 "") }

    default {
        Write-Err "Unknown command: $Command"
        Invoke-Help
        exit 1
    }
}
