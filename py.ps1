# Settings
$installPath = "C:\ProgramData\.py"  # Hidden install path
$zipFile = "$env:TEMP\python-embed.zip"

# Get latest version from python.org
$latestInfo = Invoke-RestMethod -Uri "https://www.python.org/api/v2/downloads/release/?is_published=true&limit=1"
$latestVersion = $latestInfo.results[0].name -replace "^Python ", ""
$zipUrl = "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-embed-amd64.zip"

Write-Output "Latest Python version: $latestVersion"
Write-Output "Downloading from: $zipUrl"

# Download embeddable zip
Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile

# Extract
New-Item -Path $installPath -ItemType Directory -Force | Out-Null
Expand-Archive -Path $zipFile -DestinationPath $installPath -Force
Remove-Item $zipFile -Force

# Rename executables to appear custom
Rename-Item "$installPath\python.exe" "pyhost.exe" -Force
Rename-Item "$installPath\pythonw.exe" "pyhostw.exe" -Force

# OPTIONAL: Add to system PATH silently
$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*$installPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$envPath;$installPath", "Machine")
}

Write-Output "Python discreetly installed in: $installPath"
Write-Output "Run via: $installPath\pyhost.exe"
