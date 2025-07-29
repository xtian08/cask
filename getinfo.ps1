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
