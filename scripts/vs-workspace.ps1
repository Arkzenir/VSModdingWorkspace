#Requires -Version 5.1
<#
.SYNOPSIS
    Vintage Story Modding Workspace Manager
.DESCRIPTION
    Manages API versions, dependency mods, example mods, mod scaffolding, and builds.
    No external dependencies - uses built-in PowerShell JSON handling.
.EXAMPLE
    .\scripts\vs-workspace.ps1 status
    .\scripts\vs-workspace.ps1 fetch-api v1.19.8
    .\scripts\vs-workspace.ps1 new-mod MyMod
    .\scripts\vs-workspace.ps1 build
    .\scripts\vs-workspace.ps1 build release
#>

# No param() block - PS 5.1 parameter binding chokes on dotted version strings like "1.21.5".
# Read $args (the automatic variable) directly instead.
$Command  = if ($args.Count -gt 0) { [string]$args[0] } else { 'help' }
$CmdArgs  = if ($args.Count -gt 1) { @($args[1..($args.Count - 1)]) } else { @() }

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root          = Split-Path $PSScriptRoot -Parent
$WorkspaceJson = Join-Path $Root "workspace.json"

# ─── Output helpers ───────────────────────────────────────────────────────────
function Write-Info    { param($msg) Write-Host "i " -ForegroundColor Cyan   -NoNewline; Write-Host $msg }
function Write-Success { param($msg) Write-Host "v " -ForegroundColor Green  -NoNewline; Write-Host $msg }
function Write-Warn    { param($msg) Write-Host "! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Write-Err     { param($msg) Write-Host "x " -ForegroundColor Red    -NoNewline; Write-Host $msg }
function Write-Header  { param($msg) Write-Host "`n-- $msg --" -ForegroundColor Cyan }


# ─── PS 5.1 compat helpers ────────────────────────────────────────────────────
# PowerShell 5.1 (Windows built-in) lacks the ?? operator; use these instead.
function Coalesce { param($a, $b) if ($null -ne $a -and $a -ne '') { $a } else { $b } }
function ArgAt    { param($arr, $idx, $default='') $a = @($arr); if ($a.Count -gt $idx) { $a[$idx] } else { $default } }

# ─── JSON helpers ─────────────────────────────────────────────────────────────
function Get-Workspace  { Get-Content $WorkspaceJson -Raw | ConvertFrom-Json }
function Save-Workspace { param($ws) $ws | ConvertTo-Json -Depth 10 | Set-Content $WorkspaceJson -Encoding UTF8 }
function Get-WsValue    { param([string]$Key) (Get-Workspace).$Key }

# ─── help ─────────────────────────────────────────────────────────────────────
function Invoke-Help {
    Write-Host ""
    Write-Host "Vintage Story Modding Workspace Manager" -ForegroundColor White
    Write-Host ""
    Write-Host "  Build:" -ForegroundColor Cyan
    Write-Host "    build [debug|release]        Build the active mod (default: debug)"
    Write-Host "      debug   -> dotnet build -c Debug   (output: mods\<mod>\bin\Debug\<vsver>\Mods\)"
    Write-Host "      release -> dotnet build -c Release (output: mods\<mod>\Releases\*.zip)"
    Write-Host ""
    Write-Host "  API management:" -ForegroundColor Cyan
    Write-Host "    fetch-api <version>          Clone vsapi and check out the version commit (e.g. 1.19.8)"
    Write-Host "    list-api                     List all downloaded API versions"
    Write-Host "    use-api <version>            Switch the active API version"
    Write-Host ""
    Write-Host "  Game source repos:" -ForegroundColor Cyan
    Write-Host "    fetch-gamesrc <name> [ver]   Clone a game source repo (essentials, survival)"
    Write-Host "    list-gamesrc                 List all fetched game source repos"
    Write-Host ""
    Write-Host "  Dependency / example mods:" -ForegroundColor Cyan
    Write-Host "    add-dep <path-or-url>        Add a dependency mod (local path or git URL)"
    Write-Host "    remove-dep <name>            Remove a dependency mod from scope"
    Write-Host "    add-example <path-or-url>    Add an example mod (local path or git URL)"
    Write-Host "    remove-example <name>        Remove an example from scope"
    Write-Host "    list-deps                    List all dependency mods in scope"
    Write-Host "    list-examples                List all example mods in scope"
    Write-Host ""
    Write-Host "  Target mod:" -ForegroundColor Cyan
    Write-Host "    new-mod <ModName>            Scaffold a new mod project from scratch"
    Write-Host "    import-mod <src> [Name]      Import existing mod (folder, zip, or git URL)"
    Write-Host "    use-mod <ModName>            Set the active target mod"
    Write-Host "    list-mods                    List all mods in the mods\ folder"
    Write-Host ""
    Write-Host "  Git workflow:" -ForegroundColor Cyan
    Write-Host "    publish-mod [branch] [remote]   Commit mod to a branch and push (default: mod/{modid})"
    Write-Host "    export-mod <git-url>             Push mod as a standalone repo to a remote URL"
    Write-Host "    reset [clean]                    Reset workspace.json to neutral state"
    Write-Host "                                     'clean' also removes local api\, gamesrc\, mods\, etc."
    Write-Host ""
    Write-Host "  Workspace:" -ForegroundColor Cyan
    Write-Host "    status                       Show current workspace configuration"
    Write-Host "    init                         Create directory structure (run once)"
    Write-Host ""
}

# ─── init ─────────────────────────────────────────────────────────────────────
function Invoke-Init {
    Write-Header "Initialising workspace"
    @("api", "dependencies", "examples", "mods", "gamesrc") | ForEach-Object {
        $p = Join-Path $Root $_
        if (-not (Test-Path $p)) { New-Item -ItemType Directory -Path $p | Out-Null }
    }
    Write-Success "Created: api\  dependencies\  examples\  mods\  gamesrc\"
    Write-Info    "Next step: .\scripts\vs-workspace.ps1 fetch-api 1.19.8"
}

# ─── status ───────────────────────────────────────────────────────────────────
function Invoke-Status {
    Write-Header "Workspace Status"
    $ws = Get-Workspace

    Write-Host "  Root:           " -NoNewline; Write-Host $Root -ForegroundColor White
    Write-Host ""
    Write-Host "  Game Version:   " -NoNewline; Write-Host (Coalesce $ws.gameVersion  "unset") -ForegroundColor White
    Write-Host "  API Version:    " -NoNewline; Write-Host (Coalesce $ws.apiVersion   "unset") -ForegroundColor White
    Write-Host "  .NET Target:    " -NoNewline; Write-Host (Coalesce $ws.dotnetTarget "unset") -ForegroundColor White
    Write-Host "  Game Directory: " -NoNewline; Write-Host (Coalesce $ws.gameDirectory "unset") -ForegroundColor White
    Write-Host "  Target Mod:     " -NoNewline
    if ($ws.targetMod) { Write-Host $ws.targetMod -ForegroundColor White }
    else               { Write-Host "! not set -- run: use-mod <ModName>" -ForegroundColor Yellow }
    Write-Host ""

    if ($ws.apiVersion) {
        $apiPath = Join-Path (Join-Path (Join-Path $Root "api") $ws.apiVersion) "vsapi"
        if (Test-Path $apiPath) { Write-Success "API source found:    api\$($ws.apiVersion)\vsapi" }
        else                    { Write-Warn    "API source missing:  api\$($ws.apiVersion)\vsapi  -- run: fetch-api $($ws.apiVersion)" }
    }

    if ($ws.gameDirectory) {
        $gd = [System.Environment]::ExpandEnvironmentVariables($ws.gameDirectory)
        $apiDll = Join-Path $gd "VintagestoryAPI.dll"
        if (Test-Path $apiDll) { Write-Success "Game install found:  $gd" }
        else                   { Write-Warn    "Game install not found at: $gd" }
    }

    Write-Host ""
    Write-Host "  Dependencies in scope:" -ForegroundColor Cyan
    if (@($ws.dependencies).Count -eq 0) { Write-Host "    (none)" }
    else {
        foreach ($d in @($ws.dependencies)) {
            $p = Join-Path (Join-Path $Root "dependencies") $d
            if (Test-Path $p) { Write-Host "    v $d" -ForegroundColor Green }
            else               { Write-Host "    x $d  (folder missing)" -ForegroundColor Red }
        }
    }

    Write-Host ""
    Write-Host "  Examples in scope:" -ForegroundColor Cyan
    if (@($ws.examples).Count -eq 0) { Write-Host "    (none)" }
    else {
        foreach ($e in @($ws.examples)) {
            $p = Join-Path (Join-Path $Root "examples") $e
            if (Test-Path $p) { Write-Host "    v $e" -ForegroundColor Green }
            else               { Write-Host "    x $e  (folder missing)" -ForegroundColor Red }
        }
    }

    Write-Host ""
    Write-Host "  Game source repos:" -ForegroundColor Cyan
    $gamesrcDir = Join-Path $Root "gamesrc"
    $fetched = @(Get-ChildItem $gamesrcDir -Directory -ErrorAction SilentlyContinue)
    if ($fetched.Count -eq 0) { Write-Host "    (none) -- run: fetch-gamesrc essentials / fetch-gamesrc survival" }
    else { foreach ($g in $fetched) { Write-Host "    v $($g.Name)" -ForegroundColor Green } }
    Write-Host ""
}

# ─── version commit helper ───────────────────────────────────────────────────
# Searches a cloned repo for a commit matching the requested version.
# Tries exact string match first; if that fails, parses all commit messages for
# semantic version strings and returns the closest one (highest version <= requested,
# then lowest version > requested).  Returns $null if no version commits exist at all.
function Find-VersionCommit {
    param([string]$RepoPath, [string]$Label)

    $label = $Label.TrimStart("v")
    $logOutput = @(git -C $RepoPath log --format="%H %s" 2>&1 |
                   Where-Object { $_ -notmatch '^fatal:' })
    if ($logOutput.Count -eq 0) { return $null }

    # Step 1 - exact string match
    $exactLine = $logOutput |
                 Where-Object { $_ -match [regex]::Escape($label) } |
                 Select-Object -First 1
    if ($exactLine) {
        $hash   = ($exactLine -split '\s+')[0]
        $parts  = $exactLine -split '\s+', 2
        $subj   = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
        return [PSCustomObject]@{ Hash = $hash; Subject = $subj; MatchedVersion = $label; IsExact = $true }
    }

    # Step 2 - parse requested version as System.Version
    $reqVer = $null
    try { $reqVer = [System.Version]$label } catch { return $null }

    # Step 3 - collect all version-like strings across all commits
    # git log is newest-first, so first occurrence of each version = newest commit for it
    $versionRx   = [regex]'\b(\d+\.\d+(?:\.\d+)?(?:\.\d+)?)\b'
    $seen        = @{}
    $candidates  = New-Object 'System.Collections.Generic.List[object]'

    foreach ($line in $logOutput) {
        $rxMatches = $versionRx.Matches($line)
        foreach ($m in $rxMatches) {
            $verStr = $m.Value
            if ($seen.ContainsKey($verStr)) { continue }
            $ver = $null
            try { $ver = [System.Version]$verStr } catch { continue }
            $seen[$verStr] = $true
            $hash  = ($line -split '\s+')[0]
            $parts = $line -split '\s+', 2
            $subj  = if ($parts.Count -gt 1) { $parts[1] } else { $parts[0] }
            $candidates.Add([PSCustomObject]@{
                Hash = $hash; Subject = $subj; Version = $ver; VersionStr = $verStr
            })
        }
    }

    if ($candidates.Count -eq 0) { return $null }

    # Step 4 - sort: highest version <= requested first, then lowest version > requested
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

# ─── fetch-api ────────────────────────────────────────────────────────────────
function Invoke-FetchApi {
    param([string]$Version)
    if (-not $Version) { Write-Err "Usage: fetch-api <version>  (e.g. 1.19.8)"; exit 1 }

    # Strip any leading 'v' - the repo has no tags, version is matched in commit messages
    $label = $Version.TrimStart("v")
    $dest  = Join-Path (Join-Path (Join-Path $Root "api") $label) "vsapi"

    if (Test-Path $dest) {
        Write-Warn "Already exists: api\$label\vsapi -- skipping clone."
        Write-Info "To update, delete the folder and re-run."
        return
    }

    Write-Header "Fetching vsapi for version $label"
    Write-Info "Cloning master branch (the vsapi repo has no release tags - version commits are found by searching history)..."
    New-Item -ItemType Directory -Path (Join-Path (Join-Path $Root "api") $label) -Force | Out-Null

    # Full clone - repo is small and we need history to find the version commit
    git clone https://github.com/anegostudios/vsapi.git $dest
    if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; exit 1 }

    $result = Find-VersionCommit $dest $label
    if ($result) {
        if ($result.IsExact) {
            Write-Info "Found: $($result.Subject)"
        } else {
            Write-Warn "Exact version '$label' not found -- closest match: $($result.MatchedVersion)"
            Write-Info "Commit: $($result.Subject)"
        }
        git -C $dest checkout $result.Hash --quiet
        if ($LASTEXITCODE -ne 0) { Write-Err "Checkout failed."; exit 1 }
        Write-Success "Checked out vsapi at $($result.MatchedVersion) (commit $($result.Hash.Substring(0,7)))"
    } else {
        Write-Warn "No version commits found in vsapi history -- repo is at latest master HEAD."
        Write-Warn "Browse commits at: https://github.com/anegostudios/vsapi/commits/master"
    }

    Invoke-UseApi $label
}

function Invoke-ListApi {
    Write-Header "Available API versions"
    $apiDir = Join-Path $Root "api"
    if (-not (Test-Path $apiDir) -or @(Get-ChildItem $apiDir -Directory).Count -eq 0) {
        Write-Warn "No API versions downloaded yet."; return
    }
    $active = Get-WsValue "apiVersion"
    Get-ChildItem $apiDir -Directory | ForEach-Object {
        if ($_.Name -eq $active) { Write-Host "  * $($_.Name)  (active)" -ForegroundColor Green }
        else                     { Write-Host "  o $($_.Name)" }
    }
}

function Invoke-UseApi {
    param([string]$Version)
    if (-not $Version) { Write-Err "Usage: use-api <version>"; exit 1 }
    $Version = $Version.TrimStart("v")
    if (-not (Test-Path (Join-Path (Join-Path (Join-Path $Root "api") $Version) "vsapi"))) {
        Write-Err "API version '$Version' not found.  Run: fetch-api $Version"; exit 1
    }
    $ws = Get-Workspace; $ws.apiVersion = $Version; Save-Workspace $ws
    Write-Success "Active API version set to: $Version"
}

# ─── fetch-gamesrc / list-gamesrc ─────────────────────────────────────────────
# Known game source repos. Add more here as Anegostudios publishes them.
$Script:KnownGameSrcRepos = @{
    "essentials" = "https://github.com/anegostudios/vsessentialsmod.git"
    "survival"   = "https://github.com/anegostudios/vssurvivalmod.git"
}

function Invoke-FetchGameSrc {
    param([string]$Name, [string]$Version = "")
    if (-not $Name) {
        Write-Err "Usage: fetch-gamesrc <name> [version]"
        Write-Host ""
        Write-Host "  Known repos:" -ForegroundColor Cyan
        foreach ($k in $Script:KnownGameSrcRepos.Keys) {
            Write-Host "    $k   $($Script:KnownGameSrcRepos[$k])"
        }
        exit 1
    }

    $Name = $Name.ToLower()

    if (-not $Script:KnownGameSrcRepos.ContainsKey($Name)) {
        Write-Err "Unknown game source repo: '$Name'"
        Write-Info "Known names: $($Script:KnownGameSrcRepos.Keys -join ', ')"
        Write-Info "To add unlisted repos, clone manually into gamesrc\<name>\"
        exit 1
    }

    $url  = $Script:KnownGameSrcRepos[$Name]
    $dest = Join-Path (Join-Path $Root "gamesrc") $Name

    if (Test-Path $dest) {
        Write-Warn "Already exists: gamesrc\$Name -- skipping clone."
        Write-Info "To update to a newer version, delete gamesrc\$Name and re-run."
        return
    }

    Write-Header "Fetching game source: $Name"
    New-Item -ItemType Directory -Path (Join-Path $Root "gamesrc") -Force | Out-Null

    Write-Info "Cloning $url"
    Write-Info "No release tags exist - searching commit history for version if specified..."
    git clone $url $dest
    if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; exit 1 }

    if ($Version) {
        $label  = $Version.TrimStart("v")
        $result = Find-VersionCommit $dest $label
        if ($result) {
            if ($result.IsExact) {
                Write-Info "Found: $($result.Subject)"
            } else {
                Write-Warn "Exact version '$label' not found -- closest match: $($result.MatchedVersion)"
                Write-Info "Commit: $($result.Subject)"
            }
            git -C $dest checkout $result.Hash --quiet
            if ($LASTEXITCODE -ne 0) { Write-Err "Checkout failed."; exit 1 }
            Write-Success "Checked out $Name at $($result.MatchedVersion) (commit $($result.Hash.Substring(0,7)))"
        } else {
            Write-Warn "No version commits found in $Name history -- repo is at latest master HEAD."
            Write-Warn "Browse commits at: $($url -replace '\.git$','')/commits/master"
        }
    } else {
        Write-Success "Cloned $Name at latest master HEAD -> gamesrc\$Name"
        Write-Info "To check out a specific version: delete gamesrc\$Name and re-run with a version number."
    }
}

function Invoke-ListGameSrc {
    Write-Header "Game source repos"
    $gamesrcDir = Join-Path $Root "gamesrc"
    if (-not (Test-Path $gamesrcDir) -or @(Get-ChildItem $gamesrcDir -Directory -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Warn "No game source repos fetched yet."
        Write-Info "Run: fetch-gamesrc essentials   or   fetch-gamesrc survival"
        return
    }
    Write-Host "  Fetched:" -ForegroundColor Cyan
    Get-ChildItem $gamesrcDir -Directory | ForEach-Object {
        $commitLine = git -C $_.FullName log --oneline -1 2>$null
        Write-Host "    v $($_.Name)" -ForegroundColor Green -NoNewline
        if ($commitLine) { Write-Host "   ($commitLine)" } else { Write-Host "" }
    }
    Write-Host ""
    Write-Host "  Available to fetch:" -ForegroundColor Cyan
    foreach ($k in $Script:KnownGameSrcRepos.Keys) {
        $fetched = Test-Path (Join-Path $gamesrcDir $k)
        if (-not $fetched) { Write-Host "    o $k" }
    }
}

# ─── scope helpers ────────────────────────────────────────────────────────────
function Add-ToScope {
    param([string]$Scope, [string]$FolderName, [string]$Source)
    $dest = Join-Path (Join-Path $Root $Scope) $FolderName
    if (Test-Path $dest) { Write-Warn "${Scope}\${FolderName} already exists -- skipping." }
    elseif ($Source -match "^https?://" -or $Source -match "^git@") {
        Write-Info "Cloning $Source -> $Scope\$FolderName"
        git clone --depth 1 $Source $dest
        if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; exit 1 }
    } elseif (Test-Path $Source) {
        Write-Info "Copying $Source -> $Scope\$FolderName"
        Copy-Item -Recurse $Source $dest
    } else { Write-Err "Source not found and not a URL: $Source"; exit 1 }

    $ws   = Get-Workspace
    $existingItems = @($ws.$Scope | Where-Object { $null -ne $_ -and $_ -ne '' })
    $list = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $existingItems) { $list.Add($item) }
    if (-not $list.Contains($FolderName)) {
        $list.Add($FolderName); $ws.$Scope = $list.ToArray(); Save-Workspace $ws
        Write-Success "Added $FolderName to $Scope scope."
    } else { Write-Info "$FolderName already in scope." }
}

function Remove-FromScope {
    param([string]$Scope, [string]$Name)
    $ws = Get-Workspace
    $ws.$Scope = @($ws.$Scope | Where-Object { $_ -ne $Name })
    Save-Workspace $ws
    Write-Success "Removed '$Name' from $Scope scope (folder not deleted)."
}

function Invoke-AddDep     { param($s,$n="") if(-not $s){Write-Err "Usage: add-dep <path-or-url> [name]";exit 1}; if(-not $n){$n=[IO.Path]::GetFileNameWithoutExtension($s.TrimEnd("/\"))}; Add-ToScope "dependencies" $n $s }
function Invoke-RemoveDep  { param($n) if(-not $n){Write-Err "Usage: remove-dep <name>";exit 1}; Remove-FromScope "dependencies" $n }
function Invoke-AddExample { param($s,$n="") if(-not $s){Write-Err "Usage: add-example <path-or-url> [name]";exit 1}; if(-not $n){$n=[IO.Path]::GetFileNameWithoutExtension($s.TrimEnd("/\"))}; Add-ToScope "examples" $n $s }
function Invoke-RemoveExample { param($n) if(-not $n){Write-Err "Usage: remove-example <name>";exit 1}; Remove-FromScope "examples" $n }

function Invoke-ListDeps {
    Write-Header "Dependencies in scope"
    $ws = Get-Workspace
    if (@($ws.dependencies).Count -eq 0) { Write-Host "  (none)"; return }
    foreach ($d in @($ws.dependencies)) {
        $p = Join-Path (Join-Path $Root "dependencies") $d
        if (Test-Path $p) { Write-Host "  v $d" -ForegroundColor Green } else { Write-Host "  x $d  (folder missing)" -ForegroundColor Red }
    }
}

function Invoke-ListExamples {
    Write-Header "Examples in scope"
    $ws = Get-Workspace
    if (@($ws.examples).Count -eq 0) { Write-Host "  (none)"; return }
    foreach ($e in @($ws.examples)) {
        $p = Join-Path (Join-Path $Root "examples") $e
        if (Test-Path $p) { Write-Host "  v $e" -ForegroundColor Green } else { Write-Host "  x $e  (folder missing)" -ForegroundColor Red }
    }
}

# ─── list-mods / use-mod ──────────────────────────────────────────────────────
function Invoke-ListMods {
    Write-Header "Mods"
    $modsDir = Join-Path $Root "mods"
    $active  = Get-WsValue "targetMod"
    if (-not (Test-Path $modsDir) -or @(Get-ChildItem $modsDir -Directory).Count -eq 0) {
        Write-Warn "No mods yet.  Run: new-mod <ModName>"; return
    }
    Get-ChildItem $modsDir -Directory | ForEach-Object {
        if ($_.Name -eq $active) { Write-Host "  * $($_.Name)  (active)" -ForegroundColor Green }
        else                     { Write-Host "  o $($_.Name)" }
    }
}

function Invoke-UseMod {
    param([string]$Name)
    if (-not $Name) { Write-Err "Usage: use-mod <ModName>"; exit 1 }
    if (-not (Test-Path (Join-Path (Join-Path $Root "mods") $Name))) {
        Write-Err "Mod folder not found: mods\$Name"; exit 1
    }
    $ws = Get-Workspace; $ws.targetMod = $Name; Save-Workspace $ws
    Write-Success "Active target mod set to: $Name"
}

# ─── new-mod ──────────────────────────────────────────────────────────────────
function Invoke-NewMod {
    param([string]$Name)
    if (-not $Name) { Write-Err "Usage: new-mod <ModName>"; exit 1 }

    $ws      = Get-Workspace
    $modId   = $Name.ToLower() -replace '[^a-z0-9]', ''
    $vsVer   = Coalesce $ws.apiVersion   "1.19.8"
    $dotnet  = Coalesce $ws.dotnetTarget "net7.0"
    $gameVer = Coalesce $ws.gameVersion  "1.19.0"
    $gameDir = Coalesce $ws.gameDirectory "C:\Program Files\Vintagestory"
    $dest    = Join-Path (Join-Path $Root "mods") $Name

    if (Test-Path $dest) { Write-Err "Mod folder already exists: mods\$Name"; exit 1 }

    Write-Header "Scaffolding mod: $Name"

    # ── Directory structure ────────────────────────────────────────────────────
    @(
        "source",
        "resources\assets\$modId\blocktypes",
        "resources\assets\$modId\itemtypes",
        "resources\assets\$modId\entities",
        "resources\assets\$modId\recipes",
        "resources\assets\$modId\lang",
        "resources\assets\$modId\patches",
        "Properties",
        "deps",
        "external"
    ) | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $dest $_) -Force | Out-Null }

    # ── .gitignore ─────────────────────────────────────────────────────────────
    @"
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
"@ | Set-Content (Join-Path $dest ".gitignore") -Encoding UTF8

    # ── Directory.Build.props ──────────────────────────────────────────────────
    @"
<Project>
  <!--
    Directory.Build.props - mod identity and shared compiler settings.
    Auto-imported by MSBuild before every .csproj in this folder.
    Edit ModName, ModVersion, Description, Side here - modinfo.json is generated from these.
  -->

  <!-- Mod identity -->
  <PropertyGroup>
    <ModName>$Name</ModName>
    <ModType>code</ModType>
    <ModVersion>1.0.0</ModVersion>
    <ModId>$modId</ModId>
    <Description>A Vintage Story mod.</Description>
    <Side>universal</Side>
    <RequiredOnClient>true</RequiredOnClient>
    <RequiredOnServer>true</RequiredOnServer>
  </PropertyGroup>

  <!-- Authors -->
  <ItemGroup>
    <ModInfoAuthors Include="Author" />
  </ItemGroup>

  <!-- Compiler settings -->
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
    <AppendRuntimeIdentifierToOutputPath>false</AppendRuntimeIdentifierToOutputPath>
  </PropertyGroup>

  <!-- Shared paths -->
  <PropertyGroup>
    <ProjectDir>`$(MSBuildProjectDirectory)</ProjectDir>
    <AssetsDir>`$(ProjectDir)/resources/assets</AssetsDir>
    <!-- Drop extra DLLs into /external and they are referenced automatically -->
    <ExternalLibDir>`$(ProjectDir)/external</ExternalLibDir>
  </PropertyGroup>

  <!-- Machine-specific path overrides (gitignored) -->
  <Import Project="Properties/localSettings.props"
          Condition="Exists('Properties/localSettings.props')" />

</Project>
"@ | Set-Content (Join-Path $dest "Directory.Build.props") -Encoding UTF8

    # ── Common.Build.targets ──────────────────────────────────────────────────
    @"
<Project>
  <!--
    Common.Build.targets - shared MSBuild logic for every <ModName>_<vsver>.csproj.

    Each .csproj must define before importing this file:
      `$(VSVersion)       - e.g. 1.19 or 1.20
      `$(TargetFramework) - e.g. net7.0
      `$(GameDirectory)   - resolved via localSettings.props or env vars
      <Dependencies>      - MSBuild items with Version metadata (for modinfo.json)
  -->

  <!-- Output paths - Debug and Release builds coexist by VS version -->
  <PropertyGroup>
    <OutputDir>bin/`$(Configuration)/`$(VSVersion)/Mods</OutputDir>
    <OutputPath>`$(OutputDir)/`$(ModId)</OutputPath>
    <!-- Assembly named ModName_vsver.dll (e.g. MyMod_1.19.dll) -->
    <AssemblyName>`$(MSBuildProjectName)</AssemblyName>
    <RootNamespace>$Name</RootNamespace>
  </PropertyGroup>

  <!-- Game assembly references -->
  <ItemGroup>
    <Reference Include="VintagestoryAPI" HintPath="`$(GameDirectory)/VintagestoryAPI.dll"     Private="false" />
    <Reference Include="VintagestoryLib" HintPath="`$(GameDirectory)/VintagestoryLib.dll"     Private="false" />
    <Reference Include="VSSurvivalMod"   HintPath="`$(GameDirectory)/Mods/VSSurvivalMod.dll"  Private="false" />
    <Reference Include="VSEssentials"    HintPath="`$(GameDirectory)/Mods/VSEssentials.dll"   Private="false" />
    <Reference Include="Newtonsoft.Json" HintPath="`$(GameDirectory)/Lib/Newtonsoft.Json.dll" Private="false" />
  </ItemGroup>

  <!-- Vendored per-version deps: any DLL inside deps/*-{vsver}/ is referenced automatically -->
  <ItemGroup>
    <Reference Include="`$(ProjectDir)/deps/*-`$(VSVersion)/*.dll" Private="false"
               Condition="Exists('`$(ProjectDir)/deps')" />
  </ItemGroup>

  <!-- External / ad-hoc DLLs dropped into /external -->
  <ItemGroup>
    <Reference Include="`$(ExternalLibDir)/**/*.dll" Private="false"
               Condition="Exists('`$(ExternalLibDir)')" />
  </ItemGroup>

  <!-- Generate modinfo.json from Directory.Build.props properties -->
  <Target Name="GenerateModInfo" BeforeTargets="Build">
    <PropertyGroup>
      <_ModInfoContent>{
  "type": "`$(ModType)",
  "name": "`$(ModName)",
  "modid": "`$(ModId)",
  "version": "`$(ModVersion)",
  "description": "`$(Description)",
  "authors": [ @(ModInfoAuthors->'&quot;%(Identity)&quot;', ', ') ],
  "dependencies": { @(Dependencies->'&quot;%(Identity)&quot;: &quot;%(Version)&quot;', ', ') },
  "side": "`$(Side)",
  "requiredOnClient": `$(RequiredOnClient),
  "requiredOnServer": `$(RequiredOnServer)
}</_ModInfoContent>
    </PropertyGroup>
    <MakeDir Directories="`$(OutputPath)" />
    <WriteLinesToFile File="`$(OutputPath)/modinfo.json"
                      Lines="`$(_ModInfoContent)"
                      Overwrite="true"
                      WriteOnlyWhenDifferent="true" />
  </Target>

  <!--
    Symlink resources/assets into the output folder.
    Asset edits are immediately visible to the game - no rebuild needed.
  -->
  <Target Name="LinkAssets" AfterTargets="GenerateModInfo" BeforeTargets="Build">
    <RemoveDir Directories="`$(OutputPath)/assets" />
    <Exec Condition="'`$(OS)' == 'Windows_NT'"
          Command="mklink /D &quot;`$(OutputPath)\assets&quot; &quot;`$(AssetsDir)&quot;" />
    <Exec Condition="'`$(OS)' != 'Windows_NT'"
          Command="ln -sf &quot;`$(AssetsDir)&quot; &quot;`$(OutputPath)/assets&quot;" />
  </Target>

  <!--
    Package release zip - only in Release configuration.
    Output: Releases/{modid}_{modver}_vs{vsver}.zip
    Contains only what the player needs: DLL, modinfo.json, assets.
  -->
  <Target Name="ZipRelease" AfterTargets="Build" Condition="'`$(Configuration)' == 'Release'">
    <MakeDir Directories="`$(ProjectDir)/Releases" />
    <Delete Files="`$(ProjectDir)/Releases/`$(ModId)_`$(ModVersion)_vs`$(VSVersion).zip" />
    <!-- Strip debug symbols and dependency manifest from release -->
    <Delete Files="`$(OutputPath)/`$(AssemblyName).pdb" />
    <Delete Files="`$(OutputPath)/`$(AssemblyName).deps.json" />
    <Exec Condition="'`$(OS)' == 'Windows_NT'"
          Command="powershell -Command &quot;Compress-Archive -Path '`$(OutputPath)\*' -DestinationPath '`$(ProjectDir)\Releases\`$(ModId)_`$(ModVersion)_vs`$(VSVersion).zip' -Force&quot;" />
    <Exec Condition="'`$(OS)' != 'Windows_NT'"
          Command="cd '`$(OutputPath)' &amp;&amp; zip -r '`$(ProjectDir)/Releases/`$(ModId)_`$(ModVersion)_vs`$(VSVersion).zip' ." />
  </Target>

</Project>
"@ | Set-Content (Join-Path $dest "Common.Build.targets") -Encoding UTF8

    # ── localSettings.props.template ──────────────────────────────────────────
    @"
<Project>
  <!--
    localSettings.props - machine-specific paths (NOT committed to git).
    Copy this file to Properties/localSettings.props and fill in your paths.

    Priority for GameDirectory (first non-empty wins):
      1. GameDirectory_X_XX below
      2. VINTAGE_STORY_X_XX environment variable
      3. VINTAGE_STORY environment variable

    To add a new game version:
      1. Add GameDirectory_X_XX here.
      2. Copy ${Name}_$vsVer.csproj -> ${Name}_<new>.csproj and update VSVersion + TargetFramework.
  -->
  <PropertyGroup>
    <!-- Vintage Story $vsVer -->
    <GameDirectory_$(($vsVer -replace '\.','_'))>$gameDir</GameDirectory_$(($vsVer -replace '\.','_'))>
  </PropertyGroup>
</Project>
"@ | Set-Content (Join-Path $dest "Properties\localSettings.props.template") -Encoding UTF8

    # Copy as live localSettings.props immediately
    Copy-Item (Join-Path $dest "Properties\localSettings.props.template") `
              (Join-Path $dest "Properties\localSettings.props")

    # ── {ModName}_{vsver}.csproj ──────────────────────────────────────────────
    $vsVerKey = $vsVer -replace '\.','_'
    @"
<Project Sdk="Microsoft.NET.Sdk">
  <!--
    $Name - Vintage Story $vsVer build
    To build:
      dotnet build ${Name}_${vsVer}.csproj
      dotnet build ${Name}_${vsVer}.csproj -c Release   <- also produces Releases/*.zip
  -->

  <!-- VS version label - controls output path and release zip naming -->
  <PropertyGroup>
    <VSVersion>$vsVer</VSVersion>
  </PropertyGroup>

  <!-- .NET target framework for VS $vsVer -->
  <PropertyGroup>
    <TargetFramework>$dotnet</TargetFramework>
  </PropertyGroup>

  <!-- Mod dependencies (written into generated modinfo.json) -->
  <ItemGroup>
    <Dependencies Include="game" Version=">=$gameVer" />
    <!-- Add more: <Dependencies Include="somedep" Version=">=1.0.0" /> -->
  </ItemGroup>

  <!--
    Game path resolution - first non-empty wins:
      1. GameDirectory_${vsVerKey} from Properties/localSettings.props
      2. VINTAGE_STORY_${vsVerKey} environment variable
      3. VINTAGE_STORY environment variable (global fallback)
  -->
  <PropertyGroup>
    <GameDirectory Condition="'`$(GameDirectory_${vsVerKey})' != ''">
      `$(GameDirectory_${vsVerKey})
    </GameDirectory>
    <GameDirectory Condition="'`$(GameDirectory)' == '' and '`$(VINTAGE_STORY_${vsVerKey})' != ''">
      `$(VINTAGE_STORY_${vsVerKey})
    </GameDirectory>
    <GameDirectory Condition="'`$(GameDirectory)' == ''">
      `$(VINTAGE_STORY)
    </GameDirectory>
  </PropertyGroup>

  <!-- Shared build logic (output paths, references, modinfo, assets, zip) -->
  <Import Project="Common.Build.targets" />

</Project>
"@ | Set-Content (Join-Path $dest "${Name}_${vsVer}.csproj") -Encoding UTF8

    # ── ModSystem entry point ─────────────────────────────────────────────────
    @"
using Vintagestory.API.Common;

[assembly: ModInfo("$Name", "$modId")]

namespace $Name;

public class ${Name}ModSystem : ModSystem
{
    public override void Start(ICoreAPI api)
    {
        base.Start(api);
        api.Logger.Debug("[$Name] Mod loaded.");
    }

    public override void StartClientSide(ICoreClientAPI api)
    {
    }

    public override void StartServerSide(ICoreServerAPI api)
    {
    }
}
"@ | Set-Content (Join-Path $dest "source\${Name}ModSystem.cs") -Encoding UTF8

    # ── Empty lang file ───────────────────────────────────────────────────────
    "{}" | Set-Content (Join-Path $dest "resources\assets\$modId\lang\en.json") -Encoding UTF8

    # ── Update workspace.json ─────────────────────────────────────────────────
    $ws.targetMod = $Name
    Save-Workspace $ws

    Write-Success "Scaffolded mods\$Name and set as active target mod."
    Write-Host ""
    Write-Host "  Before building:" -ForegroundColor White
    Write-Host "  1. Edit mods\$Name\Properties\localSettings.props with your game install path"
    Write-Host "  2. Open VS Code: code ."
    Write-Host "  3. Run Claude Code: claude"
    Write-Host ""
    Write-Host "  Build commands:" -ForegroundColor Cyan
    Write-Host "    .\scripts\vs-workspace.ps1 build          <- debug"
    Write-Host "    .\scripts\vs-workspace.ps1 build release  <- release + zip"
}

# ─── build ────────────────────────────────────────────────────────────────────
function Invoke-Build {
    param([string]$Mode = "debug")

    $Mode = $Mode.ToLower()
    if ($Mode -notin @("debug", "release")) {
        Write-Err "Unknown build mode '$Mode'. Use: debug  or  release"; exit 1
    }

    $ws      = Get-Workspace
    $modName = $ws.targetMod
    if (-not $modName) { Write-Err "No target mod set.  Run: use-mod <ModName>"; exit 1 }

    $modDir  = Join-Path (Join-Path $Root "mods") $modName
    $config  = if ($Mode -eq "release") { "Release" } else { "Debug" }

    # Find csproj files
    $csprojs = @(Get-ChildItem $modDir -Filter "*.csproj" -File -ErrorAction SilentlyContinue)
    if ($csprojs.Count -eq 0) {
        Write-Err "No .csproj files found in mods\$modName"
        Write-Info "Import an existing mod or run: new-mod $modName"
        exit 1
    }

    # Debug: build only the csproj matching the active apiVersion (faster iteration)
    # Release: build ALL csproj files (all supported VS versions)
    if ($Mode -eq "debug" -and $ws.apiVersion) {
        $match = @($csprojs | Where-Object { $_.Name -like "*_$($ws.apiVersion)*" })
        if ($match.Count -gt 0) { $csprojs = $match }
    }

    Write-Header "Building $modName [$config]"

    $allOk = $true
    foreach ($csproj in $csprojs) {
        Write-Host ""
        Write-Info "Project: $($csproj.Name)"
        dotnet build $csproj.FullName --configuration $config --nologo
        if ($LASTEXITCODE -ne 0) { $allOk = $false; Write-Err "Build failed: $($csproj.Name)" }
        else {
            if ($Mode -eq "debug") {
                # Derive VS version from csproj name (e.g. MyMod_1.19.csproj -> 1.19)
                if ($csproj.BaseName -match '_(\d+\.\d+)$') {
                    $vsv = $Matches[1]
                    $outPath = Join-Path (Join-Path (Join-Path (Join-Path (Join-Path $modDir "bin") "Debug") $vsv) "Mods") ($modName.ToLower() -replace '[^a-z0-9]', '')
                    Write-Success "Output -> $outPath"
                    Write-Info   "Point VS ModPath to: $(Join-Path (Join-Path (Join-Path (Join-Path $modDir 'bin') 'Debug') $vsv) 'Mods')"
                }
            } else {
                $relDir = Join-Path $modDir "Releases"
                if (Test-Path $relDir) {
                    $zips = Get-ChildItem $relDir -Filter "*.zip" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    if ($zips) { Write-Success "Release -> $($zips.FullName)" }
                }
            }
        }
    }

    Write-Host ""
    if (-not $allOk) { Write-Err "One or more builds failed."; exit 1 }
    Write-Success "All builds completed."

    if ($Mode -eq "debug") {
        Write-Host ""
        Write-Info "To load the mod: add the output Mods\ folder to your game's ModPaths,"
        Write-Info "or copy the mod folder to %APPDATA%\VintagestoryData\Mods\"
    }
}

# ─── import-mod ───────────────────────────────────────────────────────────────
function Invoke-ImportMod {
    param([string]$Source, [string]$Name = "")
    if (-not $Source) {
        Write-Err "Usage: import-mod <source> [Name]"
        Write-Host "  source can be:"
        Write-Host "    A local folder path    e.g.  C:\mods\MyMod"
        Write-Host "    A .zip file path       e.g.  C:\downloads\MyMod.zip"
        Write-Host "    A git URL              e.g.  https://github.com/someone/MyMod.git"
        exit 1
    }

    # ── Resolve destination name ───────────────────────────────────────────────
    if (-not $Name) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($Source.TrimEnd("/\"))
        # Strip common suffixes like -main, -master that come from zip downloads
        $baseName = $baseName -replace '-(main|master|src|source)$', ''
        $Name = $baseName
    }

    $dest = Join-Path (Join-Path $Root "mods") $Name

    if (Test-Path $dest) {
        Write-Err "mods\$Name already exists. Choose a different name or delete the folder first."
        exit 1
    }

    Write-Header "Importing mod: $Name"

    # ── Acquire source ─────────────────────────────────────────────────────────
    if ($Source -match "^https?://" -or $Source -match "^git@") {
        Write-Info "Cloning $Source -> mods\$Name"
        git clone --depth 1 $Source $dest
        if ($LASTEXITCODE -ne 0) { Write-Err "git clone failed."; exit 1 }

    } elseif ($Source -match "\.zip$" -and (Test-Path $Source)) {
        Write-Info "Extracting $Source -> mods\$Name"
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "vsmod_import_$Name"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive -Path $Source -DestinationPath $tmp

        # Zips from GitHub wrap everything in a subfolder - detect and unwrap
        $children = @(Get-ChildItem $tmp)
        if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
            Move-Item $children[0].FullName $dest
        } else {
            Move-Item $tmp $dest
        }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

    } elseif (Test-Path $Source) {
        Write-Info "Copying $Source -> mods\$Name"
        Copy-Item -Recurse $Source $dest

    } else {
        Write-Err "Source not found: $Source"
        exit 1
    }

    # ── Inspect what we got ────────────────────────────────────────────────────
    Write-Host ""
    Write-Header "Inspecting mod structure"

    # Read modinfo.json if present
    $modinfoPath = Join-Path $dest "modinfo.json"
    $modId   = $Name.ToLower() -replace '[^a-z0-9]', ''
    $modVer  = "unknown"
    if (Test-Path $modinfoPath) {
        try {
            $mi = Get-Content $modinfoPath -Raw | ConvertFrom-Json
            if ($mi.modid)   { $modId  = $mi.modid }
            if ($mi.version) { $modVer = $mi.version }
            Write-Success "modinfo.json   modid=$modId  version=$modVer"
        } catch {
            Write-Warn "modinfo.json found but could not be parsed."
        }
    } else {
        Write-Warn "No modinfo.json found."
    }

    # Detect csproj files
    $csprojs = @(Get-ChildItem $dest -Filter "*.csproj" -Recurse -ErrorAction SilentlyContinue)
    if ($csprojs.Count -gt 0) {
        foreach ($csp in $csprojs) { Write-Success "csproj         $($csp.Name)" }
    } else {
        Write-Warn "No .csproj found - this may be an assets-only mod, or the project file is missing."
    }

    # Detect workspace-style build files
    $hasDbp     = Test-Path (Join-Path $dest "Directory.Build.props")
    $hasCbt     = Test-Path (Join-Path $dest "Common.Build.targets")
    $hasLocal   = Test-Path (Join-Path (Join-Path $dest "Properties") "localSettings.props.template")

    if ($hasDbp -and $hasCbt) {
        Write-Success "Build system   workspace-native (Directory.Build.props + Common.Build.targets)"
        if (-not $hasLocal) {
            Write-Warn "No localSettings.props.template - you will need to set GameDirectory manually in the .csproj"
        }
    } else {
        Write-Warn "Build system   legacy / foreign (no Directory.Build.props or Common.Build.targets)"
        Write-Info "Claude Code can migrate this to the workspace build system, or work with it as-is."
    }

    # Detect source layout
    $hasSrcDir    = Test-Path (Join-Path $dest "src")
    $hasSourceDir = Test-Path (Join-Path $dest "source")
    $hasAssetsDir = Test-Path (Join-Path $dest "assets")
    $hasResDir    = Test-Path (Join-Path (Join-Path $dest "resources") "assets")

    $srcLayout    = if ($hasSourceDir) { "source\" } elseif ($hasSrcDir) { "src\" } else { "(none detected)" }
    $assetLayout  = if ($hasResDir)    { "resources\assets\" } elseif ($hasAssetsDir) { "assets\" } else { "(none detected)" }
    Write-Info "Source layout  $srcLayout"
    Write-Info "Asset layout   $assetLayout"

    # ── Set as active target ───────────────────────────────────────────────────
    $ws = Get-Workspace
    $ws.targetMod = $Name
    Save-Workspace $ws

    Write-Host ""
    Write-Success "Imported as mods\$Name and set as active target mod."
    Write-Host ""

    if (-not ($hasDbp -and $hasCbt)) {
        Write-Host "  Next steps:" -ForegroundColor White
        Write-Host "  1. Open Claude Code:  claude" -ForegroundColor Cyan
        Write-Host "  2. Tell it what to do, e.g.:" -ForegroundColor White
        Write-Host "       'Migrate this mod to the workspace build system'" -ForegroundColor DarkCyan
        Write-Host "       'Add feature X to this mod'" -ForegroundColor DarkCyan
        Write-Host "       'Fix the bug where Y happens'" -ForegroundColor DarkCyan
    } else {
        Write-Host "  Next steps:" -ForegroundColor White
        Write-Host "  1. Check mods\$Name\Properties\localSettings.props has your game path" -ForegroundColor White
        Write-Host "  2. Open Claude Code:  claude" -ForegroundColor Cyan
        Write-Host "  3. Describe what you want to change or fix" -ForegroundColor White
    }
    Write-Host ""
}

# ─── Git workflow helpers ─────────────────────────────────────────────────────
function Get-ModVersion {
    param([string]$ModDir)
    # Try Directory.Build.props first (workspace-native mods)
    $dbp = Join-Path $ModDir "Directory.Build.props"
    if (Test-Path $dbp) {
        $match = Select-String -Path $dbp -Pattern '<ModVersion>(.*?)</ModVersion>'
        if ($match) { return $match.Matches[0].Groups[1].Value.Trim() }
    }
    # Fall back to modinfo.json
    $mi = Join-Path $ModDir "modinfo.json"
    if (Test-Path $mi) {
        try {
            $obj = Get-Content $mi -Raw | ConvertFrom-Json
            if ($obj.version) { return $obj.version }
        } catch {}
    }
    return "1.0.0"
}

function Assert-GitRepo {
    $result = git -C $Root rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "The workspace folder is not a git repository."
        Write-Info "Run: git init  then  git remote add origin <url>"
        exit 1
    }
}

# ─── publish-mod ──────────────────────────────────────────────────────────────
function Invoke-PublishMod {
    param([string]$Branch = "", [string]$Remote = "origin")

    Assert-GitRepo

    $ws      = Get-Workspace
    $modName = $ws.targetMod
    if (-not $modName) { Write-Err "No target mod set.  Run: use-mod <ModName>"; exit 1 }

    $modId   = $modName.ToLower() -replace '[^a-z0-9]', ''
    $modDir  = Join-Path (Join-Path $Root "mods") $modName
    if (-not (Test-Path $modDir)) { Write-Err "Mod folder not found: mods\$modName"; exit 1 }

    if (-not $Branch) { $Branch = "mod/$modId" }

    $modVersion = Get-ModVersion $modDir
    $commitMsg  = "Mod: $modName v$modVersion"

    # Remember current branch so we can return to it
    $originalBranch = git -C $Root rev-parse --abbrev-ref HEAD 2>&1
    if ($LASTEXITCODE -ne 0 -or $originalBranch -eq "HEAD") {
        $originalBranch = "main"
    }

    Write-Header "Publishing mod: $modName"
    Write-Info "Branch:   $Branch"
    Write-Info "Remote:   $Remote"
    Write-Info "Version:  $modVersion"
    Write-Info "Returning to: $originalBranch after push"
    Write-Host ""

    # Stash any uncommitted workspace changes so we can safely switch branches
    $stashResult = git -C $Root stash --include-untracked 2>&1
    $stashed = $stashResult -notmatch 'No local changes'

    try {
        # Create or reset the mod branch from current HEAD
        git -C $Root checkout -B $Branch
        if ($LASTEXITCODE -ne 0) { Write-Err "Could not create branch '$Branch'."; exit 1 }

        # Force-add the mod folder (bypasses the workspace .gitignore)
        $relModPath = Join-Path "mods" $modName
        git -C $Root add --force $relModPath
        if ($LASTEXITCODE -ne 0) { Write-Err "git add failed."; exit 1 }

        # Also commit the current workspace.json so the branch records context
        git -C $Root add workspace.json 2>&1 | Out-Null

        $status = git -C $Root status --porcelain 2>&1
        if (-not $status) {
            Write-Warn "Nothing to commit - mod branch is already up to date."
        } else {
            git -C $Root commit -m $commitMsg
            if ($LASTEXITCODE -ne 0) { Write-Err "git commit failed."; exit 1 }
            Write-Success "Committed: $commitMsg"
        }

        # Push
        git -C $Root push $Remote $Branch --set-upstream
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Push failed - remote may not be configured."
            Write-Info "To push manually: git push $Remote ${Branch} --set-upstream"
        } else {
            Write-Success "Pushed to $Remote/$Branch"
        }
    } finally {
        # Always return to original branch
        git -C $Root checkout $originalBranch 2>&1 | Out-Null
        if ($stashed) {
            git -C $Root stash pop 2>&1 | Out-Null
        }
    }

    Write-Host ""
    Write-Success "Done. Back on branch: $originalBranch"
    Write-Info "Mod source is on branch '$Branch' and your workspace is unchanged."
}

# ─── export-mod ───────────────────────────────────────────────────────────────
function Invoke-ExportMod {
    param([string]$RemoteUrl = "")

    $ws      = Get-Workspace
    $modName = $ws.targetMod
    if (-not $modName) { Write-Err "No target mod set.  Run: use-mod <ModName>"; exit 1 }

    $modDir = Join-Path (Join-Path $Root "mods") $modName
    if (-not (Test-Path $modDir)) { Write-Err "Mod folder not found: mods\$modName"; exit 1 }

    $modVersion = Get-ModVersion $modDir
    $commitMsg  = "Mod: $modName v$modVersion"

    Write-Header "Exporting mod as standalone repo: $modName"

    # Initialise git repo inside the mod folder if not already
    $gitDir = Join-Path $modDir ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Info "Initialising git repo in mods\$modName\"
        git -C $modDir init
        git -C $modDir checkout -b main 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            # Older git uses 'master' as default; rename it
            git -C $modDir branch -m master main 2>&1 | Out-Null
        }
    }

    # Stage everything
    git -C $modDir add .
    $status = git -C $modDir status --porcelain 2>&1
    if ($status) {
        git -C $modDir commit -m $commitMsg
        if ($LASTEXITCODE -ne 0) { Write-Err "git commit failed."; exit 1 }
        Write-Success "Committed: $commitMsg"
    } else {
        Write-Info "Nothing new to commit."
    }

    # Set or update remote
    if ($RemoteUrl) {
        git -C $modDir remote remove origin 2>&1 | Out-Null
        git -C $modDir remote add origin $RemoteUrl
        Write-Info "Remote set to: $RemoteUrl"

        git -C $modDir push origin main --set-upstream --force
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Push failed. Verify the remote URL and your access rights."
            Write-Info "The local repo at mods\$modName is ready - push manually when resolved."
        } else {
            Write-Success "Pushed to $RemoteUrl"
        }
    } else {
        Write-Success "Standalone repo initialised at mods\$modName\"
        Write-Info "No remote URL given. To push later:"
        Write-Info "  git -C mods\$modName remote add origin <url>"
        Write-Info "  git -C mods\$modName push origin main --set-upstream"
    }
}

# ─── reset ────────────────────────────────────────────────────────────────────
function Invoke-Reset {
    param([string]$Mode = "")

    $clean = $Mode -eq "clean"

    Write-Header "Resetting workspace to neutral state"

    # Reset workspace.json
    $ws = Get-Workspace
    $ws.targetMod    = $null
    $ws.dependencies = @()
    $ws.examples     = @()
    Save-Workspace $ws
    Write-Success "workspace.json: targetMod cleared, dependencies and examples emptied."
    Write-Info "gameVersion, apiVersion, dotnetTarget, and gameDirectory are preserved."

    if ($clean) {
        Write-Host ""
        Write-Warn "Clean mode: the following local folders will be deleted:"
        $folders = @("mods", "api", "gamesrc", "dependencies", "examples")
        $present = @($folders | Where-Object { Test-Path (Join-Path $Root $_) })
        if ($present.Count -eq 0) {
            Write-Info "No local folders to remove."
            return
        }
        foreach ($f in $present) { Write-Host "    $f\" -ForegroundColor Yellow }
        Write-Host ""
        $confirm = Read-Host "Type YES to confirm deletion"
        if ($confirm -ne "YES") {
            Write-Info "Cancelled."
            return
        }
        foreach ($f in $present) {
            $path = Join-Path $Root $f
            Remove-Item $path -Recurse -Force
            Write-Success "Removed: $f\"
        }
        Write-Host ""
        Write-Info "Run '.\scripts\vs-workspace.ps1 init' to recreate the empty folders."
    } else {
        Write-Host ""
        Write-Info "Local folders (api\, gamesrc\, mods\, etc.) were NOT deleted."
        Write-Info "To also remove them: .\scripts\vs-workspace.ps1 reset clean"
    }
}

# ─── Router ───────────────────────────────────────────────────────────────────
switch ($Command.ToLower()) {
    "build"          { Invoke-Build        (ArgAt $CmdArgs 0 "debug") }
    "init"           { Invoke-Init }
    "status"         { Invoke-Status }
    "fetch-api"      { Invoke-FetchApi     (ArgAt $CmdArgs 0 "") }
    "list-api"       { Invoke-ListApi }
    "use-api"        { Invoke-UseApi       (ArgAt $CmdArgs 0 "") }
    "fetch-gamesrc"  { Invoke-FetchGameSrc (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "list-gamesrc"   { Invoke-ListGameSrc }
    "add-dep"        { Invoke-AddDep       (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "remove-dep"     { Invoke-RemoveDep    (ArgAt $CmdArgs 0 "") }
    "add-example"    { Invoke-AddExample   (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "remove-example" { Invoke-RemoveExample (ArgAt $CmdArgs 0 "") }
    "list-deps"      { Invoke-ListDeps }
    "list-examples"  { Invoke-ListExamples }
    "list-mods"      { Invoke-ListMods }
    "use-mod"        { Invoke-UseMod       (ArgAt $CmdArgs 0 "") }
    "import-mod"     { Invoke-ImportMod    (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "") }
    "new-mod"        { Invoke-NewMod       (ArgAt $CmdArgs 0 "") }
    "publish-mod"    { Invoke-PublishMod   (ArgAt $CmdArgs 0 "") (ArgAt $CmdArgs 1 "origin") }
    "export-mod"     { Invoke-ExportMod    (ArgAt $CmdArgs 0 "") }
    "reset"          { Invoke-Reset        (ArgAt $CmdArgs 0 "") }
    default          { Invoke-Help }
}
