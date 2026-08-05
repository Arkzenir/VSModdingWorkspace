#Requires -Version 5.1
<#
.SYNOPSIS
    First-time setup for the Vintage Story Modding Harness.
.DESCRIPTION
    Unblocks the scripts, checks prerequisites, and creates the folder structure.
    Safe to re-run.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$Root = $PSScriptRoot

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  VS Modding Harness -- First-Time Setup" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ── Unblock scripts (Windows marks downloaded files) ─────────────────────────
$onWindows = $true
$isWinVar = Get-Variable -Name IsWindows -ErrorAction SilentlyContinue
if ($null -ne $isWinVar) { $onWindows = [bool]$isWinVar.Value }

if ($onWindows) {
    try {
        Get-ChildItem -Path $Root -Filter "*.ps1" -Recurse | Unblock-File -ErrorAction SilentlyContinue
        Write-Host "[ok] Scripts unblocked." -ForegroundColor Green
    } catch {
        Write-Host "[--] Could not unblock automatically. Right-click each .ps1 -> Properties -> Unblock." -ForegroundColor Yellow
    }

    # setup.bat launches this file with -ExecutionPolicy Bypass, which only covers
    # this one process. Without setting the policy for the user, running
    # scripts\vsmod.ps1 directly afterwards still fails with
    # "running scripts is disabled on this system".
    try {
        $current = Get-ExecutionPolicy -Scope CurrentUser
        if ($current -in @("Restricted", "Undefined", "AllSigned")) {
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
            Write-Host "[ok] Execution policy set to RemoteSigned for your user account." -ForegroundColor Green
        } else {
            Write-Host "[ok] Execution policy already permits local scripts ($current)." -ForegroundColor Green
        }
    } catch {
        Write-Host "[!!] Could not set the execution policy." -ForegroundColor Yellow
        Write-Host "     Run this in PowerShell, then re-run setup:" -ForegroundColor Yellow
        Write-Host "       Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Cyan
    }
}

# ── Prerequisite checks ───────────────────────────────────────────────────────
Write-Host ""
Write-Host "Checking prerequisites:" -ForegroundColor Cyan

function Test-Tool {
    param([string]$Name, [string]$Exe, [string]$VersionArg, [string]$Why)
    $cmd = Get-Command $Exe -ErrorAction SilentlyContinue
    if ($cmd) {
        $v = ""
        try { $v = (& $Exe $VersionArg 2>&1 | Select-Object -First 1) } catch { }
        Write-Host "  [ok] $Name" -ForegroundColor Green -NoNewline
        Write-Host "  $v" -ForegroundColor DarkGray
        return $true
    }
    Write-Host "  [!!] $Name not found" -ForegroundColor Yellow -NoNewline
    Write-Host "  -- $Why" -ForegroundColor DarkGray
    return $false
}

$okGit    = Test-Tool "git"        "git"    "--version" "needed to fetch API and game source"
$okDotnet = Test-Tool "dotnet SDK" "dotnet" "--version" "needed to compile mods"

# ── harness.json ──────────────────────────────────────────────────────────────
Write-Host ""
$harness = Join-Path $Root "harness.json"
if (-not (Test-Path $harness)) {
    Copy-Item (Join-Path $Root "harness.example.json") $harness
    Write-Host "[ok] Created harness.json" -ForegroundColor Green
} else {
    Write-Host "[ok] harness.json already exists -- left alone." -ForegroundColor Green
}

# ── Folder structure ──────────────────────────────────────────────────────────
Write-Host ""
& (Join-Path $Root "scripts\vsmod.ps1") init

# ── Next steps ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Setup complete" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $okGit -or -not $okDotnet) {
    Write-Host "Install the missing tools above before building anything." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "1. Edit harness.json -- set gameDirectory to your Vintage Story install."
Write-Host "2. Download the API source once:" -ForegroundColor White
Write-Host "     .\scripts\vsmod.ps1 fetch-api 1.21.5" -ForegroundColor Cyan
Write-Host "     .\scripts\vsmod.ps1 fetch-gamesrc survival" -ForegroundColor Cyan
Write-Host "3. Start a mod:" -ForegroundColor White
Write-Host "     .\scripts\vsmod.ps1 new MyMod" -ForegroundColor Cyan
Write-Host "     .\scripts\vsmod.ps1 import https://github.com/someone/TheirMod.git" -ForegroundColor Cyan
Write-Host "4. Open your coding agent in this folder. It reads AGENTS.md automatically."
Write-Host ""
