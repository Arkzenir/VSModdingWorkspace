<#
.SYNOPSIS
    Opens a native Windows file or folder dialog and publishes the choice as an
    OliveTin entity.

.DESCRIPTION
    Run this with WINDOWS POWERSHELL (powershell.exe), not pwsh.

    WinForms dialogs require a single-threaded apartment. Windows PowerShell 5.1
    is STA by default; PowerShell 7 is MTA and has no -STA switch, so the dialog
    either fails or misbehaves there. This script has no PS7-only syntax, so
    running it under 5.1 costs nothing.

    The dialog opens on YOUR DESKTOP, which means OliveTin must be running in
    your interactive session. If OliveTin runs as a Windows service it lives in
    session 0, the dialog is drawn where nobody can see it, and the action hangs
    until it times out. The UserInteractive check below fails fast instead.

    Writes a single-row (or empty) entity file, picked.json:
        { "path": "...", "name": "...", "kind": "folder|zip|dll|file", "shown": "..." }

.EXAMPLE
    powershell.exe -NoProfile -STA -File vsmod-pick.ps1 -Mode folder
    powershell.exe -NoProfile -STA -File vsmod-pick.ps1 -Mode clear
#>

param(
    [ValidateSet("folder", "zip", "dll", "any", "clear")]
    [string]$Mode = "folder",

    [string]$OutDir = "C:/OliveTin/entities",

    # Where the dialog opens. Blank uses the last-used location.
    [string]$StartIn = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pickedFile = Join-Path $OutDir "picked.json"

function Write-Picked {
    param($Row)
    if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $tmp = "$pickedFile.tmp"
    if ($null -eq $Row) {
        [System.IO.File]::WriteAllText($tmp, "", [System.Text.UTF8Encoding]::new($false))
    } else {
        $json = $Row | ConvertTo-Json -Compress -Depth 4
        [System.IO.File]::WriteAllLines($tmp, @($json), [System.Text.UTF8Encoding]::new($false))
    }
    Move-Item $tmp $pickedFile -Force
}

# ── clear ─────────────────────────────────────────────────────────────────────
if ($Mode -eq "clear") {
    Write-Picked $null
    Write-Host "Selection cleared."
    exit 0
}

# ── interactive session check ────────────────────────────────────────────────
if (-not [Environment]::UserInteractive) {
    Write-Host "Cannot open a file dialog: this process has no desktop."
    Write-Host ""
    Write-Host "OliveTin is running as a service (session 0). Native dialogs only"
    Write-Host "work when OliveTin runs in your own interactive session - start it"
    Write-Host "from a terminal with .\OliveTin.exe instead."
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$chosen = $null
$kind   = $Mode

try {
    if ($Mode -eq "folder") {
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description         = "Select a mod source folder"
        $dlg.ShowNewFolderButton = $false
        if ($StartIn -and (Test-Path $StartIn)) { $dlg.SelectedPath = $StartIn }

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosen = $dlg.SelectedPath
        }
    }
    else {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Multiselect      = $false
        $dlg.CheckFileExists  = $true
        $dlg.RestoreDirectory = $true
        if ($StartIn -and (Test-Path $StartIn)) { $dlg.InitialDirectory = $StartIn }

        switch ($Mode) {
            "zip" {
                $dlg.Title  = "Select a mod .zip"
                $dlg.Filter = "Zip archives (*.zip)|*.zip|All files (*.*)|*.*"
            }
            "dll" {
                $dlg.Title  = "Select a dependency .dll"
                $dlg.Filter = "Assemblies (*.dll)|*.dll|All files (*.*)|*.*"
            }
            default {
                $dlg.Title  = "Select a file"
                $dlg.Filter = "All files (*.*)|*.*"
            }
        }

        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $chosen = $dlg.FileName
        }
    }
} finally {
    if ($null -ne $dlg) { $dlg.Dispose() }
}

# ── cancelled ─────────────────────────────────────────────────────────────────
# Leave any previous selection alone. Cancelling a dialog should not wipe the
# thing you picked a minute ago.
if (-not $chosen) {
    Write-Host "Cancelled - selection unchanged."
    exit 0
}

# ── publish ───────────────────────────────────────────────────────────────────
$leaf = Split-Path $chosen -Leaf
$name = $leaf -replace '\.zip$', '' -replace '\.dll$', '' -replace '\.git$', ''

# Backslashes are fine in JSON once escaped by ConvertTo-Json, and vsmod.ps1
# takes the path as a single argv element, so no shell quoting is involved.
Write-Picked ([PSCustomObject]@{
    path  = $chosen
    name  = $name
    kind  = $kind
    shown = $(if ($chosen.Length -gt 70) { "..." + $chosen.Substring($chosen.Length - 67) } else { $chosen })
})

Write-Host "Selected: $chosen"
exit 0
