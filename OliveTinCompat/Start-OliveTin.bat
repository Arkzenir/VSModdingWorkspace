@echo off
REM ============================================================================
REM  Start-OliveTin.bat  -  double-click this
REM ============================================================================
REM  A .bat is the double-click target rather than the .ps1 because Windows
REM  opens .ps1 files in Notepad when you double-click them, and because this
REM  bypasses ExecutionPolicy without you having to change a machine setting.
REM
REM  Do NOT "Run as administrator". Nothing here needs it: the harness uses
REM  junctions precisely so it works unelevated, and an elevated OliveTin
REM  cannot reliably show file dialogs to your normal desktop session.
REM
REM  Keep this file next to Start-OliveTin.ps1.
REM ============================================================================

setlocal
title OliveTin - VS Modding Harness

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-OliveTin.ps1" %*

if errorlevel 1 (
    echo.
    echo ============================================================
    echo  Startup failed - read the messages above.
    echo ============================================================
    echo.
    pause
)

endlocal
