param(
    [switch]$NoShortcut
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvPath = Join-Path $Root ".venv"
$VenvPython = Join-Path $VenvPath "Scripts\python.exe"
$Requirements = Join-Path $Root "requirements.txt"

Set-Location -LiteralPath $Root

function Write-Step([string]$Message) {
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Test-Python([string]$Executable, [string[]]$Prefix = @()) {
    try {
        & $Executable @Prefix -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)" 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

function Find-SystemPython {
    $Candidates = @(
        @{ Executable = "py.exe"; Prefix = @("-3.12") },
        @{ Executable = "py.exe"; Prefix = @("-3") },
        @{ Executable = "python.exe"; Prefix = @() }
    )

    foreach ($Candidate in $Candidates) {
        if (Get-Command $Candidate.Executable -ErrorAction SilentlyContinue) {
            if (Test-Python $Candidate.Executable $Candidate.Prefix) {
                return [PSCustomObject]$Candidate
            }
        }
    }

    $LocalPython = Join-Path $env:LOCALAPPDATA "Programs\Python\Python312\python.exe"
    if ((Test-Path -LiteralPath $LocalPython) -and (Test-Python $LocalPython)) {
        return [PSCustomObject]@{ Executable = $LocalPython; Prefix = @() }
    }
    return $null
}

try {
    Write-Host "TGA Manager automatic installer" -ForegroundColor Magenta

    if ((Test-Path -LiteralPath $VenvPython) -and -not (Test-Python $VenvPython)) {
        Write-Step "Removing an invalid virtual environment"
        Remove-Item -LiteralPath $VenvPath -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        $Python = Find-SystemPython
        if ($null -eq $Python) {
            if (-not (Get-Command "winget.exe" -ErrorAction SilentlyContinue)) {
                throw "Python 3.10+ is not installed and winget is unavailable. Install Python from https://www.python.org/downloads/ and run install.bat again."
            }

            Write-Step "Installing Python 3.12 for the current user"
            & winget.exe install --exact --id Python.Python.3.12 --scope user --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) {
                throw "winget could not install Python 3.12 (exit code $LASTEXITCODE)."
            }
            $Python = Find-SystemPython
            if ($null -eq $Python) {
                throw "Python was installed, but the installer could not locate python.exe. Sign out of Windows or restart the terminal and run install.bat again."
            }
        }

        Write-Step "Creating .venv"
        $CreateVenvArguments = @($Python.Prefix) + @("-m", "venv", $VenvPath)
        & $Python.Executable @CreateVenvArguments
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $VenvPython)) {
            throw "Failed to create the virtual environment."
        }
    }

    Write-Step "Updating pip"
    & $VenvPython -m pip install --upgrade pip setuptools wheel
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to update pip."
    }

    Write-Step "Installing application dependencies"
    & $VenvPython -m pip install --requirement $Requirements
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install dependencies from requirements.txt."
    }

    New-Item -ItemType Directory -Path (Join-Path $Root "data") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root "Telegram") -Force | Out-Null

    if (-not $NoShortcut) {
        Write-Step "Creating a desktop shortcut"
        try {
            $Shell = New-Object -ComObject WScript.Shell
            $Desktop = [Environment]::GetFolderPath("Desktop")
            $Shortcut = $Shell.CreateShortcut((Join-Path $Desktop "TGA Manager.lnk"))
            $Shortcut.TargetPath = (Join-Path $VenvPath "Scripts\pythonw.exe")
            $Shortcut.Arguments = '"' + (Join-Path $Root "main.py") + '"'
            $Shortcut.WorkingDirectory = $Root
            $Icon = Join-Path $Root "assets\app-icon.ico"
            if (Test-Path -LiteralPath $Icon) {
                $Shortcut.IconLocation = "$Icon,0"
            }
            $Shortcut.Description = "Local Telegram Desktop session manager"
            $Shortcut.Save()
        }
        catch {
            Write-Warning "The application is installed, but the desktop shortcut could not be created: $($_.Exception.Message)"
        }
    }

    Write-Host "`nTGA Manager is ready." -ForegroundColor Green
    Write-Host "Launch it with run.bat or the desktop shortcut."
    Write-Host "Telegram Desktop can be downloaded from the Settings page."
    exit 0
}
catch {
    Write-Host "`nInstallation error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
