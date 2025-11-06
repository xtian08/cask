$programName = "Microsoft 365 Apps for enterprise - en-us"

$installed = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* ,
                          HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
             Where-Object { $_.DisplayName -eq $programName }

if ($installed) {
    
    # Variables
    $url = "https://raw.githubusercontent.com/NYUAD-IT/nyrepo/refs/heads/main/ADWX.Office2024.exe"
    $outFile = "C:\Temp\wxmso\ADWX.Office2024.exe"
    $extractPath = "C:\Temp\wxmso"
    
    # Ensure target folder exists
    if (-not (Test-Path $extractPath)) { New-Item -ItemType Directory -Force -Path $extractPath | Out-Null }
    
    Write-Host "Downloading SFX file (no progress UI)..."
    
    # Faster download using HttpClient (no UI/progress)
    Add-Type -AssemblyName System.Net.Http
    $httpClient = [System.Net.Http.HttpClient]::new()
    $response = $httpClient.GetAsync($url, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result
    $fs = [System.IO.FileStream]::new($outFile, [System.IO.FileMode]::Create)
    $response.Content.CopyToAsync($fs).Wait()
    $fs.Close()
    $httpClient.Dispose()
    
    $outFile = "C:\Temp\wxmso\ADWX.Office2024.exe"
    $extractPath = "C:\Temp\wxmso"
    $ConfigPath0 = "C:\temp\wxmso\Config0.xml"
    $ConfigPath1 = "C:\temp\wxmso\removeO365.xml"
    $ConfigPath2 = "C:\temp\wxmso\Config4.xml"
    
    
    # Extract without '=' and without quotes in /D path
    Start-Process -FilePath $outFile -ArgumentList "/s1 /D$extractPath" -Wait
    Write-Host "Extraction completed."
    
    Set-Location -Path $extractPath
    
    # Run uninstall
    Start-Process -FilePath "setup.exe" -ArgumentList "/download `"$ConfigPath0`"" -Wait
    Start-Process -FilePath "setup.exe" -ArgumentList "/configure `"$ConfigPath1`"" -Wait
    Write-Host "Office uninstallation completed."
    
    Start-Process -FilePath "setup.exe" -ArgumentList "/configure `"$ConfigPath2`"" -Wait
    Write-Host "VL Installation completed."
    
    # Optional cleanup
    #Remove-Item $extractPath\*.exe -Recurse -Force
    #Remove-Item $extractPath\*.xml -Recurse -Force
    Write-Host "Cleanup completed."
    
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

    Write-Host "KMS activation completed."
} else {
    exit 0
}
