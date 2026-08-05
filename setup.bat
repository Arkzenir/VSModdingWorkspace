@echo off
setlocal
REM Convenience launcher for Windows: double-click to run setup.ps1.
REM Everything it does is also available by running scripts\vsmod.ps1 directly.

echo Launching setup...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Setup reported an error. See the output above.
)

echo.
pause
endlocal
