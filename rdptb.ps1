# Ensure the script is run with Admin Privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run as an Administrator!"
    Exit
}

# Helper function to find the target network adapter
function Get-TargetAdapter {
    return Get-NetAdapter | Where-Object { 
        $_.Name -like "*usb4*" -or 
        $_.Name -like "*thunderbolt*" -or 
        $_.InterfaceDescription -like "*usb4*" -or 
        $_.InterfaceDescription -like "*thunderbolt*" 
    } | Select-Object -First 1
}

# ==============================================================================
# PROMPT USER FOR ACTION MODE
# ==============================================================================
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  SYSTEM PROVISIONING & CLEANUP SCRIPT   " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host "1) [S] Set Configuration (Apply settings)"
Write-Host "2) [R] Remove Configuration (Clean up settings)"
Write-Host ""
$Choice = Read-Host "Please select an option (S/R)"

# Default fallback variables for network
$IPAddress = "10.10.10.2"
$PrefixLength = 24
$Gateway = "10.10.10.1"


# ==============================================================================
# MODE: SET CONFIGURATION
# ==============================================================================
if ($Choice -eq 'S' -or $Choice -eq 's') {
    Write-Host "`n--- ENTER TARGET CREDENTIALS ---" -ForegroundColor Yellow
    
    # Prompt for custom username and password
    $Username = Read-Host "Enter the username to create (e.g., test)"
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Error "Username cannot be empty!"
        Exit
    }
    
    $SecurePassword = Read-Host "Enter the password for $Username" -AsSecureString
    if ($null -eq $SecurePassword) {
        Write-Error "Password cannot be empty!"
        Exit
    }

    Write-Host "`n--- APPLYING CONFIGURATIONS ---" -ForegroundColor Green

    # 1. User Creation & Group Assignment
    if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
        Write-Host "Creating local user '$Username'..." -ForegroundColor Cyan
        New-LocalUser -Name $Username -Password $SecurePassword -Description "Admin User" -FullName "User $Username" -PasswordNeverExpires $true | Out-Null
    } else {
        Write-Host "User '$Username' already exists. Skipping creation." -ForegroundColor Yellow
    }

    Write-Host "Adding '$Username' to local groups..." -ForegroundColor Cyan
    Add-LocalGroupMember -Group "Administrators" -Member $Username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group "Remote Desktop Users" -Member $Username -ErrorAction SilentlyContinue

    # 2. Enable Remote Desktop (RDP)
    Write-Host "Enabling Remote Desktop (RDP)..." -ForegroundColor Cyan
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"

    # 3. Enable Fast User Switching
    Write-Host "Enabling Fast User Switching..." -ForegroundColor Cyan
    $SysPoliciesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path $SysPoliciesPath)) {
        New-Item -Path $SysPoliciesPath -Force | Out-Null
    }
    Set-ItemProperty -Path $SysPoliciesPath -Name "HideFastUserSwitching" -Value 0 -Type DWord -Force

    # 4. Configure Static IPv4 on USB4/Thunderbolt Adapter
    $Adapter = Get-TargetAdapter
    if ($Adapter) {
        Write-Host "Found matching adapter: '$($Adapter.Name)' ($($Adapter.InterfaceDescription))" -ForegroundColor Green
        Write-Host "Clearing existing configurations on '$($Adapter.Name)'..." -ForegroundColor Yellow
        Remove-NetIPAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $Adapter.Name -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
        
        Write-Host "Applying Static IP: $IPAddress / $Gateway..." -ForegroundColor Green
        New-NetIPAddress -InterfaceAlias $Adapter.Name -IPAddress $IPAddress -PrefixLength $PrefixLength -DefaultGateway $Gateway | Out-Null
    } else {
        Write-Warning "Could not find an adapter matching 'usb4' or 'thunderbolt'. IP configuration skipped."
    }

    Write-Host "`nConfiguration applied successfully!" -ForegroundColor Green


# ==============================================================================
# MODE: REMOVE CONFIGURATION
# ==============================================================================
} elseif ($Choice -eq 'R' -or $Choice -eq 'r') {
    Write-Host "`n--- REMOVING CONFIGURATIONS ---" -ForegroundColor Red
    
    # Prompt for username to remove
    $Username = Read-Host "Enter the username to remove (e.g., test)"
    if ([string]::IsNullOrWhiteSpace($Username)) {
        Write-Error "Username cannot be empty!"
        Exit
    }

    # 1. Delete Local User
    if (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue) {
        Write-Host "Removing local user '$Username'..." -ForegroundColor Cyan
        Remove-LocalUser -Name $Username -Confirm:$false
    } else {
        Write-Host "User '$Username' not found. Skipping user removal." -ForegroundColor Yellow
    }

    # 2. Disable Remote Desktop (RDP)
    Write-Host "Disabling Remote Desktop (RDP)..." -ForegroundColor Cyan
    Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name "fDenyTSConnections" -Value 1
    Disable-NetFirewallRule -DisplayGroup "Remote Desktop"

    # 3. Disable/Hide Fast User Switching (Restores Windows Default)
    Write-Host "Disabling Fast User Switching (reverting policy)..." -ForegroundColor Cyan
    $SysPoliciesPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    if (Test-Path $SysPoliciesPath) {
        Set-ItemProperty -Path $SysPoliciesPath -Name "HideFastUserSwitching" -Value 1 -Type DWord -Force
    }

    # 4. Revert IP Adapter to DHCP
    $Adapter = Get-TargetAdapter
    if ($Adapter) {
        Write-Host "Reverting adapter '$($Adapter.Name)' back to DHCP..." -ForegroundColor Cyan
        Remove-NetIPAddress -InterfaceAlias $Adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute -InterfaceAlias $Adapter.Name -DestinationPrefix "0.0.0.0/0" -Confirm:$false -ErrorAction SilentlyContinue
        
        Set-NetIPInterface -InterfaceAlias $Adapter.Name -Dhcp Enabled
        Set-DnsClientServerAddress -InterfaceAlias $Adapter.Name -ResetServerAddresses
    } else {
        Write-Warning "Could not find an adapter matching 'usb4' or 'thunderbolt' to reset."
    }

    Write-Host "`nCleanup completed successfully!" -ForegroundColor Green

} else {
    Write-Warning "Invalid choice. Exiting script."
}
