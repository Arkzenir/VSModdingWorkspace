@echo off
setlocal

echo =============================================
echo   VS Modding Workspace -- First-Time Setup
echo =============================================
echo.
echo This will:
echo   1. Remove the "downloaded from internet" block on the PS script
echo   2. Allow local PowerShell scripts to run (current user only)
echo   3. Create the workspace folder structure
echo.
echo Press any key to continue, or close this window to cancel.
pause >nul

echo.

REM ── Step 1: Unblock the PowerShell script ─────────────────────────────────
powershell -Command "Unblock-File -Path '.\scripts\vs-workspace.ps1'" 2>nul
if %errorlevel% equ 0 (
    echo [OK] Script unblocked.
) else (
    echo [!!] Unblock failed -- you may need to right-click the script, Properties, tick Unblock.
)

REM ── Step 2: Set execution policy ──────────────────────────────────────────
powershell -Command "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force" 2>nul
if %errorlevel% equ 0 (
    echo [OK] Execution policy set to RemoteSigned for current user.
) else (
    echo [!!] Execution policy change failed -- you may need to run this as Administrator.
)

REM ── Step 3: Create workspace folder structure ──────────────────────────────
echo.
powershell -ExecutionPolicy Bypass -File ".\scripts\vs-workspace.ps1" init
if %errorlevel% neq 0 (
    echo.
    echo [!!] Setup encountered an error. See output above.
    pause
    exit /b 1
)

echo.
echo =============================================
echo   Setup complete.
echo =============================================
echo.
echo Open this folder in VS Code, then:
echo.
echo   Ctrl+Shift+P  -^>  "Run Task"  -^>  "WS: Fetch API Version"
echo   Ctrl+Shift+P  -^>  "Run Task"  -^>  "WS: Fetch Game Source (Essentials)"
echo   Ctrl+Shift+P  -^>  "Run Task"  -^>  "WS: Fetch Game Source (Survival)"
echo   Ctrl+Shift+P  -^>  "Run Task"  -^>  "WS: New Mod"
echo.
echo After that, Ctrl+Shift+B builds the active mod at any time.
echo.
pause
endlocal
