@echo off
setlocal
cd /d "%~dp0"

chcp 65001 >nul
title TGA Manager - Installation

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
set "INSTALL_EXIT=%ERRORLEVEL%"

echo.
if not "%INSTALL_EXIT%"=="0" (
  echo Installation failed. See the message above.
) else (
  echo Installation completed successfully.
)
echo.
pause
exit /b %INSTALL_EXIT%
