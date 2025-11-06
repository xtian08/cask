<#
.DESCRIPTION
  This PowerShell script is to perform preflight checks and install necessary dependencies for managing Windows systems.
.CREATED by
  Christian Mariano    
#>

####CODE

Write-Output "The EP is: $(Get-ExecutionPolicy)"
Write-Output "Running as: $(whoami)"
Write-Output "Sources : nyrepo"
$curVer = $PSVersionTable.PSVersion
Write-Output "Current PowerShell version: $curVer"

# Detect OS architecture
$arch = if ([Environment]::Is64BitOperatingSystem) {
    if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
} else {
    "x86"
}

# Detect processor architecture explicitly
$cpuArch = $ENV:PROCESSOR_ARCHITECTURE
$cpuArchWoW64 = $ENV:PROCESSOR_ARCHITEW6432

# Final decision (handles ARM too)
switch -Regex ($cpuArch + $cpuArchWoW64) {
    "ARM64" { $arch = "ARM64" }
    "AMD64" { $arch = "x64" }
    "x86"   { $arch = "x86" }
}

Write-Output "Detected Architecture: $arch"

# Start logging

$hostname = $env:COMPUTERNAME
# Start logging with hostname included in the log filename
$LogPath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_${hostname}_debug.log" #_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $LogPath -NoClobber -Force -ErrorAction SilentlyContinue -Append

if (-not (Test-Path "C:\Temp")) { New-Item -Path "C:\Temp" -ItemType Directory | Out-Null }
$LogFiledebug = "C:\Temp\debug.log"

# Run the whoami command and capture the output
$user = whoami

# Define known system account names
$systemAccounts = @(
    "NT AUTHORITY\SYSTEM",      # Local System
    "NT AUTHORITY\LOCAL SERVICE",  # Local Service
    "NT AUTHORITY\NETWORK SERVICE" # Network Service
)

$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function xBootstrap {

Write-Output "*************Check and install Dependencies*************"
#$progressPreference = 'silentlyContinue'

######### Check Nuget Provider #########

# Check if NuGet provider is installed
$nugetProvider = Get-PackageProvider -ListAvailable | Where-Object {$_.Name -eq "NuGet"}

if ($nugetProvider) {
    Write-Output "NuGet provider is installed."
} else {
    Write-Output "NuGet provider is not installed."
    # Install the NuGet provider without interaction
    Install-PackageProvider -Name NuGet -Force -Confirm:$false  -ErrorAction Ignore
}

######### Check PSGallery #########
Write-Output "*************Trust PSGallery*************"
Register-PSRepository -Default -ErrorAction SilentlyContinue
# Trust PSGallery if not already trusted
try {
    $repo = Get-PSRepository -Name PSGallery
    if ($repo.InstallationPolicy -ne 'Trusted') {
        Write-Host "Setting PSGallery as Trusted..."
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
    } else {
        Write-Host "PSGallery is already trusted."
    }
} catch {
    Exit-OnError "Failed to verify/set PSGallery trust: $_"
}

# Install the Update-InboxApp script if not already installed
if (Get-InstalledScript -Name Update-InboxApp -ErrorAction SilentlyContinue) {
    Write-Host "Update-InboxApp script is already installed. Skipping installation."
} else {
    try {
        Write-Host "Installing Update-InboxApp script..."
        Install-Script -Name Update-InboxApp -Force -ErrorAction Stop
        Write-Host "Update-InboxApp installed successfully."
    } catch {
        Exit-OnError "Failed to install Update-InboxApp script: $_"
    }
}

# Install the winget-install script if not already installed
if (Get-InstalledScript -Name winget-install -ErrorAction SilentlyContinue) {
    Write-Host "winget-install script is already installed. Skipping installation."
} else {
    try {
        Write-Host "Installing winget-install script..."
        Install-Script -Name winget-install -Force -ErrorAction Stop
        Write-Host "winget-install installed successfully."

    } catch {
        Exit-OnError "Failed to install winget-install script: $_"
    }
}


######### Check PS Modules #########
Write-Output "*************Checking PSU Module*************"

# Check if PSWindowsUpdate module is installed
$psWindowsUpdateInstalled = Get-Module -ListAvailable -Name PSWindowsUpdate

# If the module is not installed, notify the user
if (-not $psWindowsUpdateInstalled) {
    Write-Output "PSWindowsUpdate module is not installed."
        # Set the NuGet package provider to trust all repositories
    #Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    Install-Module -Name PSWindowsUpdate -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck -ErrorAction Ignore

    # Import the moduleget
    Import-Module -Name PSWindowsUpdate -Force -ErrorAction Ignore
} else {
    Write-Output "PSWindowsUpdate module is installed."
}

Write-Output "*************Checking Winget Module*************"

# Check if PSWindowsUpdate module is installed
$wgmodule = Get-Module -ListAvailable -Name Microsoft.WinGet.Client

# If the module is not installed, notify the user
if (-not $wgmodule) {
    Write-Output "Microsoft.WinGet.Client module is not installed."
    Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -AllowClobber -SkipPublisherCheck -ErrorAction Ignore | Out-Null

    # Import the moduleget
    Import-Module -Name Microsoft.WinGet.Client -Force -ErrorAction Ignore
    Write-Output "Winget module verified."
} else {
    Write-Output "Winget module is installed."
}

######### Check Winget is up to date #########
Write-Output "************* Checking Package Manager *************"
$wgAPPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget-install.ps1 -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName

function wgInstall {
    #$Force = $true
    #& "C:\Temp\psexec.exe" -accepteula -i -s powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm 'asheroto.com/winget' | iex" *>> $LogFiledebug
    $psiArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$wgAPPath`" -Force"
    Start-Process -FilePath "powershell.exe" -ArgumentList $psiArgs -Verb RunAs -Wait

    # Retry detection after install
    Start-Sleep -Seconds 5
    if ($wingetPath) {
        Write-Output "winget installed successfully at $wingetPath"
    } else {
        Write-Error "winget installation 2nd attempt."
        try {
            $psiArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$wgAPPath`" -UpdateSelf"
            Start-Process -FilePath "powershell.exe" -ArgumentList $psiArgs -Verb RunAs -Wait
        }catch {
            $psiArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$wgAPPath`" -AlternateInstallMethod"
            Start-Process -FilePath "powershell.exe" -ArgumentList $psiArgs -Verb RunAs -Wait
        }
        finally {
            Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
            Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose
        }
    }

        # Set default region if not set
    if (-not $env:winget_region) {
        $env:winget_region = "US"
        Write-Host "$env:winget_region was not set. Defaulted to: US"
    } else {
        Write-Host "$env:winget_region is already set to: $env:winget_region"
    }

}

$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
if ($wingetPath) {
    Write-Output "winget is installed at $wingetPath"
} else {
    Write-Output "winget is not installed. Attempting installation..."
    wgInstall
}
######### Check Winget is up to date #########
Write-Output "************* Checking Winget Version *************"

$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
if (Test-Path $wingetPath) {
    # Get installed winget version
    $wingetVersion = & "$wingetPath" --version
    Write-Output "Winget version (installed): $wingetVersion"

    # Get latest winget version from GitHub
    $response = Invoke-WebRequest -Uri "https://github.com/microsoft/winget-cli/releases/latest" -UseBasicParsing
    if ($response.StatusCode -eq 200) {
        if ($response.Headers.'Content-Location') {
            $latestUrl = $response.Headers.'Content-Location'
        } else {
            $latestUrl = $response.RawContent -match 'href="(/microsoft/winget-cli/releases/tag/v[0-9.]+)"' | Out-Null
            $latestUrl = "https://github.com" + $matches[1]
        }
    
        $latestVersion = $latestUrl -split "/" | Select-Object -Last 1
        $latestVersion = $latestVersion.TrimStart("v")
        Write-Output "Latest Winget version: $latestVersion"
    }

    # Normalize both versions (remove leading 'v' if present)
    $installedVersion = $wingetVersion.TrimStart("v")

    if ($installedVersion -ne $latestVersion) {
        Write-Output "Winget is outdated. Installed: $installedVersion, Latest: $latestVersion"
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force 
        try {
            wgInstall
        }
        finally {
            Write-Output "Winget updater performed"
        }
        
    } else {
        Write-Output "Winget is up to date."
    }

} else {
    Write-Output "winget.exe not found."
    wgInstall
}

# Check if PsExec.exe is already present
$psexecPath = "C:\temp\psexec.exe"
if (-Not (Test-Path $psexecPath)) {
    # Create the directory if it doesn't exist
    if (-Not (Test-Path "C:\temp")) {
        New-Item -Path "C:\temp" -ItemType Directory
    }

    # Download PsExec.exe
    $t="C:\Temp\psexec.exe"; if (!(Test-Path $t)) { $u="https://download.sysinternals.com/files/PSTools.zip"; $z="$env:TEMP\pst.zip"; $d="$env:TEMP\pst"; iwr $u -OutFile $z; Expand-Archive $z $d -Force; ni (Split-Path $t) -ea 0 -ItemType Directory; cp "$d\PsExec64.exe" $t -Force; rm $z; rm $d -Recurse -Force }

}

######### Check PWSH Binary #########
Write-Output "************* Update PS7 *************"
$pwshPATH = Get-ChildItem -Path "C:\Program Files\" -Filter pwsh.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
Write-Output "pwsh.exe path: $pwshPATH"

$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName
Start-Process -FilePath $wingetPath -ArgumentList @(
    "install", "--id", "Microsoft.PowerShell", "--silent", 
    "--accept-package-agreements", "--accept-source-agreements", "-e"
) -Wait -NoNewWindow

}

1..2 | ForEach-Object { xBootstrap }
#Clean old logs

$folders = @("C:\Temp", "C:\ProgramData\Airwatch\unifiedagent\logs", "C:\Users\Public")
$patterns = @("xxxxxxx", "Powershell transcript")
foreach ($folder in $folders) {
    Get-ChildItem -Path $folder -Recurse -File -Include *.log,*.txt -ErrorAction SilentlyContinue | 
    ForEach-Object {
        $lines = Get-Content -Path $_.FullName -TotalCount 3
        if ($patterns | Where-Object { $lines -match $_ }) {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "Deleted: $($_.FullName)"
        }
    }
}
Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope Process -Force

# Please enter to terminate
Write-Host "Press Enter to exit..."
#s[void][System.Console]::ReadLine()
#exit 0
