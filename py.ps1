# Settings
$installPath = "C:\ProgramData\.py"  # Hidden install path
$zipFile = "$env:TEMP\python-embed.zip"

# Get latest stable version by parsing HTML from python.org
$versionsPage = Invoke-WebRequest -Uri "https://www.python.org/ftp/python/" -UseBasicParsing
$versionPattern = '\d+\.\d+\.\d+/'
$latestVersion = ($versionsPage.Links | Where-Object { $_.href -match $versionPattern }) |
    ForEach-Object { $_.href.TrimEnd('/') } |
    Sort-Object -Descending |
    Select-Object -First 1

# Construct download URL
$zipUrl = "https://www.python.org/ftp/python/$latestVersion/python-$latestVersion-embed-amd64.zip"

Write-Output "Latest Python version: $latestVersion"
Write-Output "Downloading from: $zipUrl"

# Download embeddable zip
Invoke-WebRequest -Uri $zipUrl -OutFile $zipFile

# Extract
New-Item -Path $installPath -ItemType Directory -Force | Out-Null
Expand-Archive -Path $zipFile -DestinationPath $installPath -Force
Remove-Item $zipFile -Force

# Rename executables
Rename-Item "$installPath\python.exe" "pyhost.exe" -Force
Rename-Item "$installPath\pythonw.exe" "pyhostw.exe" -Force

# OPTIONAL: Add to system PATH
$envPath = [Environment]::GetEnvironmentVariable("Path", "Machine")
if ($envPath -notlike "*$installPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$envPath;$installPath", "Machine")
}

Write-Output "Python $latestVersion discreetly installed in: $installPath"
Write-Output "Run using: $installPath\pyhost.exe"
