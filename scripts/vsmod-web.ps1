#Requires -Version 5.1
<#
.SYNOPSIS
    Adapter that lets OliveTin drive vsmod.ps1 without a terminal.

.DESCRIPTION
    Place this next to vsmod.ps1 in the harness scripts\ folder.

    Every OliveTin action calls it the same way:

        vsmod-web.ps1 <answer> <verb> [args...]

    <answer> is the reply to any Read-Host prompt vsmod.ps1 raises. Pass a
    single dash ("-") when the verb does not prompt, which is all of them
    except "remove" and "cache remove".

    Examples:
        vsmod-web.ps1 - build release
        vsmod-web.ps1 - use GlowingMushroom
        vsmod-web.ps1 GlowingMushroom remove GlowingMushroom
        vsmod-web.ps1 YES cache remove api/1.21.5

    Why the dot-source: vsmod.ps1 calls Read-Host on destructive verbs. In a
    web UI there is no console to answer it, so the call would hang until the
    action timed out. Dot-sourcing runs vsmod.ps1 in this scope, where the
    Read-Host function defined below shadows the real cmdlet and returns the
    confirmation OliveTin already collected in the browser. vsmod.ps1 itself
    is not modified.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Console setup ─────────────────────────────────────────────────────────────
# Without this, box-drawing characters and any non-ASCII output from dotnet or
# git arrive in the browser as mojibake.
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch { }

# Keep dotnet/git output parseable and uncoloured for the web log view.
$env:DOTNET_CLI_UI_LANGUAGE  = "en"
$env:DOTNET_NOLOGO           = "1"
$env:GIT_TERMINAL_PROMPT     = "0"   # never block waiting for credentials
$env:GIT_PAGER               = "cat"

# ── Argument split ────────────────────────────────────────────────────────────
if ($args.Count -lt 2) {
    Write-Host "Usage: vsmod-web.ps1 <answer|-> <verb> [args...]"
    exit 2
}

$Answer  = [string]$args[0]
$Forward = @($args[1..($args.Count - 1)])

# Trailing empty strings are OliveTin sending an optional argument that the
# user left blank. vsmod.ps1 defaults those itself, so drop them rather than
# passing "" through as a positional.
while ($Forward.Count -gt 0 -and [string]::IsNullOrWhiteSpace($Forward[-1])) {
    if ($Forward.Count -eq 1) { break }
    $Forward = @($Forward[0..($Forward.Count - 2)])
}

# ── Confirmation shim ─────────────────────────────────────────────────────────
if ($Answer -ne "-") {
    function Read-Host {
        param([string]$Prompt, [switch]$AsSecureString, [switch]$MaskInput)
        Write-Host "$Prompt : $Answer  (answered by OliveTin)"
        return $Answer
    }
}

# ── Run ───────────────────────────────────────────────────────────────────────
$vsmod = Join-Path $PSScriptRoot "vsmod.ps1"
if (-not (Test-Path $vsmod)) {
    Write-Host "vsmod.ps1 not found next to this script: $vsmod"
    exit 2
}

Write-Host "> vsmod $($Forward -join ' ')"
Write-Host ""

# vsmod.ps1 calls `exit 1` on any failure, which terminates this process with
# the same code, so OliveTin sees a red button. Nothing extra needed here.
. $vsmod @Forward

exit 0
