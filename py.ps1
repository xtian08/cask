# Discreet Python Embed Installer with pip and obfuscation
$ErrorActionPreference = 'Stop'

# === SETTINGS ===
$installPath = "C:\ProgramData\.netcache"
$zipFile = "$env:TEMP\python-embed.zip"
$pipBootstrap = "$env:TEMP\get-pip.py"

# === 1. Scrape latest Python version ===
$versionsPage = Invoke-WebRequest -Uri "https://www.python.org/ftp/python/" -UseBasicParsing
$versionPattern = '\d+\.\d+\.\d+/'
$latestVersion = ($versionsPage.Links | Where-Object { $_.href -match $versionPattern }) |
    ForEach-Object { $_.href.TrimEnd('/') } |
    Sort-Object -Descending |
    Select-Object -First 1

# Build ZIP URL
$zipUrl = "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-embed-amd64.zip"
Write-Output "Latest Python version: $latestVersion"
Write-Output "Downloading from: $zipUrl"

# === 2. Download and extract ===
if (Test-Path $installPath) {
    Remove-Item -Path $installPath -Recurse -Force
}
Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile
Expand-Archive -Path $zipFile -DestinationPath $installPath -Force
Remove-Item $zipFile -Force

# === 3. Enable 'import site' ===
$pthFile = Get-ChildItem -Path $installPath -Filter "python*._pth" | Select-Object -First 1
if ($pthFile) {
    (Get-Content $pthFile.FullName) |
        ForEach-Object { $_ -replace '^\s*#\s*import site', 'import site' } |
        Set-Content $pthFile.FullName
    Write-Output "'import site' enabled in $($pthFile.Name)"
} else {
    Write-Warning "Could not find .pth file to enable 'import site'"
}

# === 4. Rename python executables ===
$pythonExe   = Join-Path $installPath "python.exe"
$pyhostExe   = Join-Path $installPath "svcproc.exe"  # obfuscated name
$pythonwExe  = Join-Path $installPath "pythonw.exe"
$pyhostwExe  = Join-Path $installPath "svcprocw.exe"

if ((Test-Path $pythonExe) -and (-not (Test-Path $pyhostExe))) {
    Rename-Item $pythonExe $pyhostExe -Force
}
if ((Test-Path $pythonwExe) -and (-not (Test-Path $pyhostwExe))) {
    Rename-Item $pythonwExe $pyhostwExe -Force
}

# === 5. Add to PATH (optional)
$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$env:Path += ";C:\ProgramData\.netcache\Scripts"
$env:Path += ";C:\ProgramData\.netcache"
if ($envPath -notlike "*$installPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$envPath;$installPath", "Machine")
    Write-Output "Added $installPath to PATH."
}

# === 6. Install pip manually ===
Invoke-WebRequest -Uri "https://bootstrap.pypa.io/get-pip.py" -OutFile $pipBootstrap
Start-Process -FilePath "$pyhostExe" -ArgumentList "`"$pipBootstrap`"" -Wait -NoNewWindow
Remove-Item $pipBootstrap -Force

Write-Output "✅ Python + pip installed discreetly at: $installPath"
Write-Output "➡️ Use Python: $installPath\svcproc.exe"
Write-Output "➡️ Use pip: svcproc.exe -m pip install <package>"
