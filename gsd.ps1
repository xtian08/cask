<#
.DESCRIPTION
  This PowerShell script is invoke windows update via PS module
.CREATED by
  Christian Mariano    
#>

param (
    #[bool]$RunWindowsUpdate = $false
    [string]$RunWindowsUpdate = "yes"
    #[switch]$RunWindowsUpdate
)

####CODE

Write-Output "The EP is: $(Get-ExecutionPolicy)"
Write-Output "Running as: $(whoami)"

# Clean up old log files (older than 7 days)
$logDirectory = "C:\ProgramData\AirWatch\UnifiedAgent\Logs"
$logRetentionDays = 7
$logFiles = Get-ChildItem -Path $logDirectory -Filter "ADWX_*.log" -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$logRetentionDays) } 
foreach ($logFile in $logFiles) {
    try {
        Remove-Item -Path $logFile.FullName -ErrorAction Stop
        Write-Output "Deleted old log file: $($logFile.FullName)"
    } catch {
        Write-Output "Failed to delete log file: $($logFile.FullName) - $_"
    }
}

# Start logging

$hostname = $env:COMPUTERNAME
# Start logging with hostname included in the log filename
$LogPath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_GSD_Patch_${hostname}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $LogPath -NoClobber

# Run the whoami command and capture the output
$user = whoami

# Define known system account names
$systemAccounts = @(
    "NT AUTHORITY\SYSTEM",      # Local System
    "NT AUTHORITY\LOCAL SERVICE",  # Local Service
    "NT AUTHORITY\NETWORK SERVICE" # Network Service
)

################ Start Script ################
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Output "*************GSD Initiated at $date*************"
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

# Install the Update-InboxApp script
try {
    Write-Host "Installing Update-InboxApp script..."
    Install-Script -Name Update-InboxApp -Force -ErrorAction Stop
    Write-Host "Update-InboxApp installed successfully."
} catch {
    Exit-OnError "Failed to install Update-InboxApp script: $_"
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

######### Check Winget is uptodate #########
Write-Output "*************Checking Package Manager*************"

######### Check Winget is up to date #########
Write-Output "************* Checking Package Manager *************"

$windowsAppsPath = "$env:ProgramFiles\WindowsApps"
$wingetPath = Get-ChildItem -Path $windowsAppsPath -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force |
              Select-Object -First 1 -ExpandProperty FullName

if ($wingetPath) {
    Write-Output "winget is installed at $wingetPath"
} else {
    Write-Output "winget is not installed. Attempting installation..."
    
    function Install-Winget {
        $url = "https://raw.githubusercontent.com/asheroto/winget-install/refs/heads/master/winget-install.ps1"
        $command = "iwr -UseBasicParsing '$url' | iex"
        
        Start-Process -FilePath "C:\Temp\psexec.exe" `
            -ArgumentList "-accepteula", "-i", "-s", "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command `
            -WindowStyle Hidden -Wait
    }

    Install-Winget

    # Retry detection after install
    Start-Sleep -Seconds 5
    $wingetPath = Get-ChildItem -Path $windowsAppsPath -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force |
                  Select-Object -First 1 -ExpandProperty FullName
    if ($wingetPath) {
        Write-Output "winget installed successfully at $wingetPath"
    } else {
        Write-Error "winget installation failed."
        exit 1
    }
}

# Set default region if not set
if (-not $env:winget_region) {
    $env:winget_region = "US"
    Write-Host "`$env:winget_region was not set. Defaulted to: US"
} else {
    Write-Host "`$env:winget_region is already set to: $env:winget_region"
}

# Validate winget is functioning
try {
    echo Y | & $wingetPath list --accept-source-agreements --disable-interactivity --locale "en-US" *> $null
    echo Y | & $wingetPath list *> $null
    Write-Output "winget is working."
} catch {
    Write-Error "winget failed to execute."
    exit 1
}
# Remove Choco
if ((Test-Path 'C:\ProgramData\chocolatey\bin\choco.exe')) {
    Remove-Item -Recurse -Force "$env:ChocolateyInstall" #-WhatIf
    [System.Text.RegularExpressions.Regex]::Replace([Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment').GetValue('PATH', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames).ToString(), [System.Text.RegularExpressions.Regex]::Escape("$env:ChocolateyInstall\bin") + '(?>;)?', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | %{[System.Environment]::SetEnvironmentVariable('PATH', $_, 'User')}
    [System.Text.RegularExpressions.Regex]::Replace([Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment\').GetValue('PATH', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames).ToString(),  [System.Text.RegularExpressions.Regex]::Escape("$env:ChocolateyInstall\bin") + '(?>;)?', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | %{[System.Environment]::SetEnvironmentVariable('PATH', $_, 'Machine')}

    if ($env:ChocolateyBinRoot -ne '' -and $env:ChocolateyBinRoot -ne $null) { Remove-Item -Recurse -Force "$env:ChocolateyBinRoot" } #-WhatIf }
    if ($env:ChocolateyToolsRoot -ne '' -and $env:ChocolateyToolsRoot -ne $null) { Remove-Item -Recurse -Force "$env:ChocolateyToolsRoot" } #-WhatIf }
    [System.Environment]::SetEnvironmentVariable("ChocolateyBinRoot", $null, 'User')
    [System.Environment]::SetEnvironmentVariable("ChocolateyToolsLocation", $null, 'User')
    Write-Output "Choco removed"
}

######### Perform Windows Update #########
Write-Output "*************Running Windows OS Updates*************"

if ($RunWindowsUpdate.ToLower() -eq "yes") {
    $usoClientCommand = 'Start-Process -FilePath "C:\Windows\System32\UsoClient.exe" -ArgumentList "startinteractivescan" -NoNewWindow -Wait'
    if ($RunWindowsUpdate) {

        # OSD is imaging / GSD is patching
        if (($(whoami) -eq 'NT AUTHORITY\SYSTEM') -and (Test-Path 'C:\temp\New Text Document.txt')) {
            Write-Output "Detected as **OSD** process is runinng - Logs below look for ***PSUsection***"
            $PSUlogFilePath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_PSUJobFS_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $windowsUpdateCommand = 'Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose -Confirm:$false'
            # Using Start-Process to capture output
            Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -Command $windowsUpdateCommand" -RedirectStandardOutput $PSUlogFilePath -Wait

            Invoke-Expression $usoClientCommand
            Remove-Item 'C:\temp\New Text Document.txt' -Force
            Write-Output "File removed"
        } else {
            Write-Output "Detected as **GSD** process is runinng - Logs below look for ***PSUsection***"
            $PSUlogFilePath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_PSUJob_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
            $windowsUpdateCommand = 'Install-WindowsUpdate -NotCategory "Drivers" -NotTitle "Firmware" -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose -Confirm:$false'
            # Using Start-Process to capture output
            Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -Command $windowsUpdateCommand" -RedirectStandardOutput $PSUlogFilePath -Wait
            Invoke-Expression $usoClientCommand
        }
    }    
            
} else {
    Write-Output "Detected as **SKIPPED** process is runinng - Logs below look for ***PSUsection***"
    $PSUlogFilePath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_PSUJob_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    Write-Output "Windows Update not initiated. Set the -RunWindowsUpdate parameter to 'yes' to execute." | Out-File $PSUlogFilePath
    
}

######### Perform Apps Update #########
# Define the URLs and paths
$psexecPath = "C:\temp\psexec.exe"

# Ensure PsExec.exe is available
if (-Not (Test-Path $psexecPath)) {
$t="C:\Temp\psexec.exe"; if (!(Test-Path $t)) { $u="https://download.sysinternals.com/files/PSTools.zip"; $z="$env:TEMP\pst.zip"; $d="$env:TEMP\pst"; iwr $u -OutFile $z; Expand-Archive $z $d -Force; ni (Split-Path $t) -ea 0 -ItemType Directory; cp "$d\PsExec64.exe" $t -Force; rm $z; rm $d -Recurse -Force }
}

# Function to update apps using winget
function Update-Apps {
    param(
        [int]$TimeoutMinutes = 30
    )

    # Log the start of the update
    Write-Output "************* Running Apps Updates (Timeout ${TimeoutMinutes} mins) *************"

    #Perform InboxApp Updates
    Get-AppxPackage | Update-InboxApp

    # Locate winget.exe
    $windowsAppsPath = "$env:ProgramFiles\WindowsApps"
    $wingetPath = Get-ChildItem -Path $windowsAppsPath -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force |
                Select-Object -First 1 -ExpandProperty FullName

    Write-Output "winget.exe path: $wingetPath"

    if (Test-Path $wingetPath) {
        # Get installed winget version
        $wingetVersion = & "$wingetPath" --version
        Write-Output "Winget version (installed): $wingetVersion"

        # Get latest winget version from GitHub
        $latestWingetRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $latestWingetVersion = $latestWingetRelease.tag_name.TrimStart("v")  # Strip leading "v" if present
        Write-Output "Winget version (latest): $latestWingetVersion"

        # Normalize both versions (remove leading 'v' if present)
        $installedVersion = $wingetVersion.TrimStart("v")
        $latestVersion = $latestWingetVersion.TrimStart("v")

        if ($installedVersion -ne $latestVersion) {
            Write-Output "Winget is outdated. Installed: $installedVersion, Latest: $latestVersion"
            wgInstall
        } else {
            Write-Output "Winget is up to date."
        }

    } else {
        Write-Output "winget.exe not found."
        wgInstall
    }

    if ($wingetPath) {
        Write-Host "winget.exe found at: $wingetPath"

        # Define arguments for winget.exe
        $wingetArgs = @(
            "upgrade",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--all",
            "--include-unknown",
            "--force",
            "--disable-interactivity",
            "--verbose",
            "--silent"
        ) -join " "

        # Define log file path with timestamp
        $logFilePath = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_WingetJob_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

        # Build the command with proper quoting
        $wingetCommand = "`"$wingetPath`" $wingetArgs"
        $cmdCommand = "/accepteula -s cmd /c `"$wingetCommand`""

        # Open a new PowerShell window to monitor the log and auto-close when "Job completed" is found
        $watch = "while(1){Clear-Host; `$l=Get-Content '$logFilePath'; `$l|%{Write-Host `$_.Trim()}; if(`$l -match 'Job completed'){break}; Start-Sleep 2}; exit"
        Start-Process powershell -ArgumentList "-NoExit", "-Command $watch" -ErrorAction SilentlyContinue

        # Start winget.exe via PsExec
        $process = Start-Process -FilePath $psexecPath -ArgumentList "$cmdCommand > $logFilePath 2>&1" -PassThru -Wait -NoNewWindow 

        # Wait for completion or timeout
        $timeout = $TimeoutMinutes * 60
        $process.WaitForExit($timeout * 1000)
        Add-Content -Path $logFilePath -Value "Job completed"

        if (Test-Path $wingetPath) {
            & $wingetPath list | Out-File -FilePath $logFilePath -Append
            Write-Host "Installed apps list has been logged to $logFilePath"
        } 

        # Log handling
        if (Test-Path $logFilePath) {
            $logContent = Get-Content -Path $logFilePath
            Write-Host "Log File Content:`n$logContent"
        } else {
            Write-Host "Log file not found."
        }

        # Check if the process is still running
        if (!$process.HasExited) {
            Write-Host "winget.exe did not complete within the timeout. Terminating the process."
            $process.Kill()
        } else {
            Write-Host "winget.exe completed successfully."
        }
        
    } else {
        Write-Host "winget.exe not found on the system."
    }
}

# Run Update-Apps twice
1..2 | ForEach-Object { Update-Apps -TimeoutMinutes 30 }

#Verify 7-zip
function Get-7ZipVersionByPath {
    # Define the default 7-Zip installation path
    $possiblePaths = @(
        "C:\Program Files\7-Zip\7z.exe",
        "C:\Program Files (x86)\7-Zip\7z.exe"
    )

    # Check each path for 7-Zip
    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            # Get the file version
            $fileVersion = (Get-Item $path).VersionInfo.FileVersion
            Write-Output "7-Zip version: $fileVersion (Path: $path)"
            return
        }
    }

    Write-Output "7-Zip is not installed or not found in default locations."
}

# Execute the function
Get-7ZipVersionByPath | Out-file c:\temp\7zip.log 

######### Remove Silverlight #########

Write-Output "*************Checking for Silverlight*************"

# Check if Silverlight is installed
if (Get-WmiObject -Query "SELECT * FROM Win32_Product WHERE Name LIKE '%Silverlight%'") {
    Write-Output "Silverlight is installed. Removing"
    
    # Uninstall Silverlight
    $uninstallResult = (Uninstall-Package -name 'Microsoft Silverlight' -force)

} else {
    Write-Output "Silverlight is not installed."
}

######### Perform Log4j-Scan #########

Write-Output "*************Checking log4j*************"

# Check if log4j is installed
# Define variables
$jar_file = "c:\temp\log4jscan-latest.jar"
$log_file = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_log4j.log"

# Function to check if the log4j JAR file exists
function Check-JarExistence {
    param (
        [string]$jar_file
    )
    return Test-Path $jar_file
}


# Check if log4j JAR file exists
if (Check-JarExistence -jar_file $jar_file) {
    Write-Output "Using existing JAR file: $jar_file"
} else {
    # Get the latest release URL
    $latest_url = (Invoke-WebRequest -Uri "https://api.github.com/repos/logpresso/CVE-2021-44228-Scanner/releases/latest" -UseBasicParsing | ConvertFrom-Json).assets | Where-Object { $_.browser_download_url -like "*.jar" } | Select-Object -ExpandProperty browser_download_url

    # Download the latest .jar file
    Invoke-WebRequest -Uri $latest_url -OutFile $jar_file -UseBasicParsing

    # Check if download was successful
    if ($?) {
        Write-Output "Downloaded: $jar_file"
    } else {
        Write-Output "Failed to download JAR file. Exiting."
    }
}

# Run the scanner
try {
    # Execute the Java command and redirect output to the log file
    java -jar $jar_file --scan-log4j1 --no-empty-report --force-fix --all-drives > $log_file
    if ($LASTEXITCODE -eq 0) {
        Write-Output "Scan completed. Log file: $log_file"
    } else {
        throw "Command failed with exit code $LASTEXITCODE"
    }
} catch {
    # Output failure message
    Write-Output "Failed to execute log4j scan"
}


######### Perform Ghostscript #########

Write-Output "*************Checking Ghostscript*************"

function 7zipCheck {

# Get the current PATH environment variable
$currentPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)

# Check if 7-Zip path is already in the PATH
if ($currentPath -like "*$sevenZipPath*") {
    Write-Output "7-Zip path is already in the PATH environment variable."
} else {
    # Add the 7-Zip path to the PATH environment variable
    $newPath = "$currentPath;$sevenZipPath"
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, [System.EnvironmentVariableTarget]::Machine)
    Write-Output "7-Zip path added to the PATH environment variable."
}

# Display the updated PATH environment variable
$updatedPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
Write-Output "Updated PATH: $updatedPath"
}

function DownloadGS {


# Define the GitHub repository and release tag
$repository = "ArtifexSoftware/ghostpdl-downloads"
$tag = "latest"

# Get the release information from GitHub API
$releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/$tag"

# Loop through each asset in the release
foreach ($asset in $releaseInfo.assets) {
    $downloadUrl = $asset.browser_download_url
    $fileName = $asset.name

    # Check if the file matches the desired prefix and suffix
    if ($fileName -like "gs*.exe") {
        # Define the output file path
        $outputFile = "C:\temp\$fileName"

        # Check if the file doesn't already exist in the download folder
        if (-not (Test-Path $outputFile)) {
            # Download the asset
            Invoke-WebRequest -Uri $downloadUrl -OutFile $outputFile
            Write-Output "Downloaded $fileName to $outputFile"
        } else {
            Write-Output "$fileName already exists in the download folder."
        }
    }
}
}

# Function to find and run uninstgs.exe
function Remove-GsFoldersAndRegistry {
    $paths = @(
        "C:\Program Files\gs",
        "C:\Program Files (x86)\gs"
    )

    $registryKeys = @(
        "HKLM:\SOFTWARE\Artifex\GPL Ghostscript",
        "HKLM:\SOFTWARE\GPL Ghostscript"
    )

    # Remove folders
    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Output "Successfully deleted folder: $path"
            } catch {
                Write-Error "Failed to delete folder: $path. Error: $_"
            }
        } else {
            Write-Output "Folder does not exist: $path"
        }
    }

    # Remove registry keys
    foreach ($key in $registryKeys) {
        if (Test-Path $key) {
            try {
                Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
                Write-Output "Successfully deleted registry key: $key"
            } catch {
                Write-Error "Failed to delete registry key: $key. Error: $_"
            }
        } else {
            Write-Output "Registry key does not exist: $key"
        }
    }
}

function Uninstall-Ghostscript {
    $paths = @(
        "C:\Program Files\gs",
        "C:\Program Files (x86)\gs"
    )

    $uninstallers = @()

    # Search for uninstgs.exe in the specified directories and their subdirectories
    foreach ($path in $paths) {
        Write-Output "Searching for uninstgs.exe in $path..."
        $results = Get-ChildItem -Path $path -Recurse -Filter uninstgs.exe -ErrorAction SilentlyContinue
        $uninstallers += $results
    }

    if ($uninstallers.Count -gt 0) {
        Write-Output "Found the following uninstallers:"
        $uninstallers | ForEach-Object { Write-Output " - $($_.FullName)" }

        # Run each found uninstaller
        foreach ($uninstaller in $uninstallers) {
            Write-Output "Attempting to run uninstaller: $($uninstaller.FullName)"
            try {
                Start-Process -FilePath $uninstaller.FullName -ArgumentList "/S" -Wait -ErrorAction Stop
                Write-Output "Successfully ran uninstaller: $($uninstaller.FullName)"
            } catch {
                Write-Output "Failed to run uninstaller: $($uninstaller.FullName). Error: $_"
            }
        }
    } else {
        Write-Output "No uninstgs.exe found in the specified directories."

    }
}

# Function to install the appropriate Ghostscript version using Chocolatey
function Install-Ghostscript {

    Set-Location C:\temp

    & "C:\Program Files\7-Zip\7z.exe" x -y -xr!$PLUGINSDIR -xr!"*.nsis" -xr!"vcredist*" -o"C:\Program Files\gs\gs10.03.1" "gs10031w64.exe"

    & "C:\Program Files\7-Zip\7z.exe" x -y -ir!"Identity-UTF16-H" -o"C:\Program Files\gs\gs10.03.1" "gs10031w64.exe"

    & "C:\Program Files\7-Zip\7z.exe" x -y -ir!bin -o"C:\Program Files\gs\gs10.03.1" "gs10031w32.exe"

    reg.exe ADD "HKLM\SOFTWARE\Artifex\GPL Ghostscript\10.03.1" /ve /d "C:\Program Files\gs\gs10.03.1" /f 
    reg.exe ADD "HKLM\SOFTWARE\GPL Ghostscript\10.03.1" /v "GS_DLL" /t REG_SZ /d "C:\Program Files\gs\gs10.03.1\bin\gsdll64.dll;C:\Program Files\gs\gs10.03.1\bin\gsdll32.dll" /f 
    reg.exe ADD "HKLM\SOFTWARE\GPL Ghostscript\10.03.1" /v "GS_LIB" /t REG_SZ /d "C:\Program Files\gs\gs10.03.1\bin;C:\Program Files\gs\gs10.03.1\lib;C:\Program Files\gs\gs10.03.1\fonts" /f

    # Check if the path exists in the PATH environment variable
    $gsPath = "C:\Program Files\gs\gs10.03.1\bin"
    if ($env:PATH -split ";" -contains $gsPath) {
        Write-Output "GS bin already in PATH."
    } else {
        Write-Output "Adding GS bin to PATH."
        $newPath = $env:PATH + ";" + $gsPath
        [System.Environment]::SetEnvironmentVariable("PATH", $newPath, [System.EnvironmentVariableTarget]::Machine)
    }

}

function Test-GhostscriptExecutable {
    # Define the paths where Ghostscript executables might be located
    $gsPaths = @(
        "C:\Program Files\gs\gs*\bin\gswin64c.exe",  # 64-bit version
        "C:\Program Files (x86)\gs\gs*\bin\gswin64c.exe",  # 64-bit version in x86 folder
        "C:\Program Files\gs\gs*\bin\gswin32c.exe",  # 32-bit version
        "C:\Program Files (x86)\gs\gs*\bin\gswin32c.exe"  # 32-bit version in x86 folder
    )

    # Iterate over each path and check if the executable exists and is executable
    foreach ($path in $gsPaths) {
        $gsExecutable = Get-ChildItem $path -ErrorAction SilentlyContinue
        if ($gsExecutable -ne $null -and $gsExecutable -is [System.IO.FileInfo]) {
            Write-Output "$($gsExecutable.FullName) is executable."
            # If you want to execute the executable, you can uncomment the line below
            # Start-Process $gsExecutable.FullName
            Write-Output "Ghostscript executable found."
            return $true
        }
    }

    Write-Output "No Ghostscript executable found."
    return $false
}

$paths = @(
    "C:\Program Files\gs",
    "C:\Program Files (x86)\gs"
)

$gsFolderExists = $false

foreach ($path in $paths) {
    if (Test-Path $path) {
        $gsFolderExists = $true
        break
    }
}

if (-not $gsFolderExists) {
    Write-Output "Ghostscript folder not found. Skipped install process."
} else {
    # Run the installation process
    Write-Output "Ghostscript folder found. Starting install process."
    7zipCheck
    DownloadGS
    Uninstall-Ghostscript
    Remove-GsFoldersAndRegistry
    Install-Ghostscript
    Test-GhostscriptExecutable
}

######### Perform Java Check #########

Write-Output "*************Checking Java*************"


# Define the path to check
$javaPath = "C:\Program Files\Java"

# Initialize the boolean parameters
$containsJDK = $false
$containsJRE = $false
$simulateUninstall = $false # Change this to $false to perform actual uninstallation

# Function to uninstall JDK or JRE
function Uninstall-Software {
    param (
        [string]$softwarePattern,
        [bool]$simulate
    )

    # Get the uninstall command from the registry
    $uninstallKeys = Get-ChildItem -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall", "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" |
                     Get-ItemProperty |
                     Where-Object { $_.DisplayName -match $softwarePattern }

    foreach ($key in $uninstallKeys) {
        if ($key.UninstallString) {
            # Replace MsiExec.exe /I with MsiExec.exe /X if found
            $uninstallCommand = $key.UninstallString -replace "MsiExec.exe /I", "MsiExec.exe /X"
            
            if ($simulate) {
                Write-Output "Simulating uninstallation of $($key.DisplayName) using command: $uninstallCommand"
            } else {
                Write-Output "Uninstalling $($key.DisplayName) using command: $uninstallCommand"
                & cmd.exe /c $uninstallCommand /quiet /norestart
            }
        }
    }
}

# Check if the path exists
if (Test-Path $javaPath) {
    # Check for subfolders containing "jdk" in their name
    $containsJDK = Get-ChildItem -Path $javaPath -Directory | Where-Object { $_.Name -like "*jdk*" } | ForEach-Object { $true }
    
    # Check for subfolders containing "jre" in their name
    $containsJRE = Get-ChildItem -Path $javaPath -Directory | Where-Object { $_.Name -like "*jre*" } | ForEach-Object { $true }
}

# Output the results and uninstall if found
if ($containsJDK) {
    Write-Output "JDK folder found. Parameter containsJDK set to True."
    Uninstall-Software -softwarePattern "SE Development Kit" -simulate $simulateUninstall
} else {
    Write-Output "No JDK folder found. Parameter containsJDK remains False."
}

if ($containsJRE) {
    Write-Output "JRE folder found. Parameter containsJRE set to True."
    Uninstall-Software -softwarePattern "Java \d+ update" -simulate $simulateUninstall
} else {
    Write-Output "No JRE folder found. Parameter containsJRE remains False."
}

# Clean Folder
Remove-Item -Path $javaPath -Force -Recurse -ErrorAction SilentlyContinue | Write-Output "Java Folder not present"
if ($containsJDK) {
    Start-Process -FilePath $wingetPath -ArgumentList "install Oracle.JDK.22"
}

if ($containsJRE) {
    Start-Process -FilePath $wingetPath -ArgumentList "install Oracle.JavaRuntimeEnvironment"
} 

######### Perform Adobe KCCC RUM updater #########
Write-Output "*************Checking Adobe*************"

# Define the URLs and paths
$psexecPath = "C:\temp\psexec.exe"
$wglogFile = "C:\temp\winget_log.txt"
$creativeCloudPath = "C:\Program Files\Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe"
$adobeRUMPath = "C:\Program Files (x86)\Common Files\Adobe\OOBE_Enterprise\RemoteUpdateManager\RemoteUpdateManager.exe"
$installerPath = "$env:TEMP\ACCC_Set-Up.exe"

# Function to run Adobe RUM silently
function Run-AdobeRUM {
    if (Test-Path $adobeRUMPath) {
        & $adobeRUMPath
    } else {
        Write-Output "Adobe Remote Update Manager is not installed."
    }
}

# Check if PsExec.exe is already present
if (-Not (Test-Path $psexecPath)) {
    # Create the directory if it doesn't exist
    if (-Not (Test-Path "C:\temp")) {
        New-Item -Path "C:\temp" -ItemType Directory
    }

    # Download PsExec.exe
    $t="C:\Temp\psexec.exe"; if (!(Test-Path $t)) { $u="https://download.sysinternals.com/files/PSTools.zip"; $z="$env:TEMP\pst.zip"; $d="$env:TEMP\pst"; iwr $u -OutFile $z; Expand-Archive $z $d -Force; ni (Split-Path $t) -ea 0 -ItemType Directory; cp "$d\PsExec64.exe" $t -Force; rm $z; rm $d -Recurse -Force }

}

# Find winget.exe
$wingetPath = Get-ChildItem -Path "C:\Program Files\" -Filter winget.exe -Recurse -ErrorAction SilentlyContinue -Force | Select-Object -First 1 -ExpandProperty FullName

if (-Not $wingetPath) {
    Write-Error "winget.exe not found."
}

# Check if Creative Cloud is installed
if (Test-Path $creativeCloudPath) {
    Write-Output "Adobe Creative Cloud is already installed."
    Run-AdobeRUM
} else {
    Write-Output "Adobe Creative Cloud is not installed. Installing using winget..."
    
    # Define the command to run winget
    $wingetCommand = "`"$wingetPath`" install --id Adobe.CreativeCloud --silent --accept-package-agreements --accept-source-agreements -e"

    # Run winget command as SYSTEM using PsExec and log the output
    Start-Process -FilePath $psexecPath -ArgumentList "/accepteula -i 1 -s cmd /c $wingetCommand > $wglogFile" -Wait -NoNewWindow

    # Output the process log file path
    Write-Output "The process output has been logged to $wglogFile"

    # Check for errors in the process log file
    if (Test-Path $wglogFile) {
        $wglogContent = Get-Content -Path $wglogFile
        if ($wglogContent) {
            Write-Output "Log file content:"
            Write-Output $wglogContent
        } else {
            Write-Output "Log file is empty."
        }
    } else {
        Write-Output "Log file not found."
    }

    # Run Adobe RUM after installation
    Run-AdobeRUM
}

# Function to force kill all Adobe Creative Cloud processes
function Kill-AdobeCreativeCloud {
    # Array of Adobe Creative Cloud processes to terminate
    $adobeProcesses = @(
        "Creative Cloud"
    )

    foreach ($process in $adobeProcesses) {
        Get-Process -Name $process -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                Write-Host "Terminated process: $($_.Name) (PID: $($_.Id))"
            } catch {
                Write-Host "Failed to terminate: $process"
            }
        }
    }
}

# Execute the function
Kill-AdobeCreativeCloud

#################################################
########## KMS Activation #########

Write-Output "*************Checking KMS Activation*************"

$hostname = $env:COMPUTERNAME
$targetKMS = "10.229.130.213"
$maskedKMS = "XXX.XXX.XXX.XXX"
$kmslogfile = "C:\ProgramData\AirWatch\UnifiedAgent\Logs\ADWX_KMSJob_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if ($hostname -like 'ADUAE*' -or $hostname -like 'NYUAD*') {
    Write-Output "Managed PC found"  >> $kmslogfile

    # Check KMS server for Windows
    $kms = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform' -Name KeyManagementServiceName -ErrorAction SilentlyContinue
    if ($kms.KeyManagementServiceName -ne $targetKMS) {
        Write-Output "KMS not set or incorrect. Setting KMS server to $maskedKMS..."  >> $kmslogfile
        cscript.exe C:\Windows\System32\slmgr.vbs /skms $targetKMS >> $kmslogfile 2>&1 | Out-Null
    } else {
        Write-Output "KMS server is already set correctly for Windows." >> $kmslogfile
    }

    # Check activation status
    $windowsStatus = cscript.exe C:\Windows\System32\slmgr.vbs /xpr | Out-String
    if ($windowsStatus -match "Volume activation will expire") {
        Write-Output "Windows is already activated (KMS lease)." >> $kmslogfile
    } else {
        Write-Output "Activating Windows..."
        cscript.exe C:\Windows\System32\slmgr.vbs /ato >> $kmslogfile 2>&1 | Out-Null
    }

    # Office activation logic
    $officePaths = Get-ChildItem -Path "C:\Program Files\Microsoft Office" -Recurse -Filter ospp.vbs -ErrorAction SilentlyContinue
    foreach ($path in $officePaths) {
        if ($path.FullName -match "Office15|Office16|Office17") {
            Write-Output "Found Office at: $($path.FullName)"  >> $kmslogfile

            Write-Output "Setting Office KMS server to $maskedKMS..."
            cscript.exe "$($path.FullName)" /sethst:$targetKMS >> $kmslogfile 2>&1 | Out-Null

            $status = cscript.exe "$($path.FullName)" /dstatus | Out-String
            if ($status -notmatch "LICENSE STATUS:  ---LICENSED---") {
                Write-Output "Activating Office..."  >> $kmslogfile
                cscript.exe "$($path.FullName)" /act >> $kmslogfile 2>&1 | Out-Null
            } else {
                Write-Output "Office already activated."  >> $kmslogfile
            }
        }
    }

} else {
    Write-Output "Not NYUAD Managed PC. Skipping KMS activation."  >> $kmslogfile
}
########################
#query Get-WinSystemLocale and echo the result
$locale = Get-WinSystemLocale
Write-output "System Locale: $locale"

$disk = Get-Disk | Where-Object { $_.IsBoot -eq $true }

if ($disk.PartitionStyle -eq 'GPT') {
    # Check if there is an EFI System Partition using the GUID
    $efiPartition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.GptType -eq '{C12A7328-F81F-11D2-BA4B-00A0C93EC93B}' }
    
    if ($efiPartition) {
        # Convert the size to MB
        $efiPartitionSizeMB = [math]::round($efiPartition.Size / 1MB, 2)
        Write-Output "Disk is EFI, EFI Partition Size: $efiPartitionSizeMB MB"
    } else {
        Write-Output "Disk is GPT but no EFI System Partition found"
    }
} else {
    Write-Output "Disk is MBR"
}

# Stop logging
Stop-Transcript

Write-Output "*************Checking old logs*************"

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
