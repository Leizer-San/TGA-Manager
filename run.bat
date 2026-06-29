@echo off
setlocal
cd /d "%~dp0"

if exist ".venv\Scripts\pythonw.exe" (
  start "" ".venv\Scripts\pythonw.exe" "%~dp0main.py"
) else (
  start "" pyw -3 "%~dp0main.py"
)
endlocal
