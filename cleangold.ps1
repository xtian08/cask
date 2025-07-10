# ========== SETTINGS ==========
$runSysprep = $true   # Set to $false if you don't want to auto-run Sysprep
$sysprepArgs = "/oobe /generalize /shutdown /quiet"
# ==============================

Write-Host "`n==== [PRE-SYSPREP CLEANUP SCRIPT] ====" -ForegroundColor Cyan

# 1. Clean superseded components
Write-Host "`n[1/6] DISM Cleanup (StartComponentCleanup)..."
dism /Online /Cleanup-Image /StartComponentCleanup

Write-Host "`n[2/6] DISM ResetBase (permanently removes old update uninstall data)..."
dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# 2. Remove non-essential provisioned apps
Write-Host "`n[3/6] Removing non-essential provisioned apps..."
$appxKeep = 'Store|Framework|Input|ShellExperienceHost|StartMenuExperienceHost'
Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -notmatch $appxKeep
} | ForEach-Object {
    Write-Host "  Removing $($_.DisplayName)"
    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName
}

# 3. Disable Defender real-time protection (temporary)
Write-Host "`n[4/6] Disabling Defender real-time protection..."
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue

# 4. Clean SoftwareDistribution and temp folders
Write-Host "`n[5/6] Cleaning update cache and temp files..."
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv

$env:temp, "$env:SystemRoot\Temp" | ForEach-Object {
    Write-Host "  Cleaning temp: $_"
    Remove-Item "$_\*" -Recurse -Force -ErrorAction SilentlyContinue
}

# 5. Clear event logs
Write-Host "`n[6/6] Clearing Event Logs..."
Get-WinEvent -ListLog * | Where-Object { $_.RecordCount -gt 0 } | ForEach-Object {
    Write-Host "  Clearing log: $($_.LogName)"
    wevtutil cl "$($_.LogName)"
}

# 6. Optionally run Sysprep
if ($runSysprep) {
    Write-Host "`n✅ Cleanup complete. Launching Sysprep with: $sysprepArgs" -ForegroundColor Green
    Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList $sysprepArgs -Wait
} else {
    Write-Host "`n✅ Cleanup complete. You can now run Sysprep manually." -ForegroundColor Green
}
