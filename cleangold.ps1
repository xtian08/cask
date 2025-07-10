Write-Host "`n==== Starting Pre-Sysprep Cleanup ====" -ForegroundColor Cyan

# Step 1: Clean up superseded components (but preserve latest updates)
Write-Host "`n[1/4] Running StartComponentCleanup..."
dism /Online /Cleanup-Image /StartComponentCleanup

# Step 2: Reset base — removes ability to uninstall older updates (safely keeps latest cumulative update)
Write-Host "`n[2/4] Running ResetBase to reduce WIM size..."
dism /Online /Cleanup-Image /StartComponentCleanup /ResetBase

# Step 3: Remove provisioned apps (keep essentials only)
Write-Host "`n[3/4] Removing non-essential provisioned apps..."
$appxKeep = 'Store|Framework|Input|ShellExperienceHost|StartMenuExperienceHost'
Get-AppxProvisionedPackage -Online | Where-Object {
    $_.DisplayName -notmatch $appxKeep
} | ForEach-Object {
    Write-Host "Removing provisioned app: $($_.DisplayName)"
    Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName
}

# Step 4: Optional — Clean up update residuals (useful for Windows 10/11)
Write-Host "`n[4/4] Deleting temporary update files..."
Stop-Service wuauserv -Force
Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv

Write-Host "`n✅ Pre-Sysprep Cleanup Complete. You can now run Sysprep." -ForegroundColor Green
