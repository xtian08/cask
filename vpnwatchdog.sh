#!/bin/bash

# Simple Network Monitor Installer
# Executes $tempest with sudo on network changes

set -e

WATCHDOG_BIN="/usr/local/bin/ip-watchdog.sh"
PROFILE="/opt/cisco/secureclient/vpn/profile/DefaultProfile.xml"

echo "[*] Installing IP Watchdog with corrected IP detection..."

# --------------------------
# 1. Install watchdog script
# --------------------------
cat <<EOF | sudo tee "$WATCHDOG_BIN" >/dev/null
#!/usr/bin/env bash

PROFILE="/opt/cisco/secureclient/vpn/profile/DefaultProfile.xml"

write_profile() {
cat <<'XML_EOF' | sudo tee "$PROFILE" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<AnyConnectProfile xmlns="http://schemas.xmlsoap.org/encoding/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://schemas.xmlsoap.org/encoding/ AnyConnectProfile.xsd">
	<ClientInitialization>
		<UseStartBeforeLogon UserControllable="true">false</UseStartBeforeLogon>
		<AutomaticCertSelection UserControllable="true">false</AutomaticCertSelection>
		<ShowPreConnectMessage>false</ShowPreConnectMessage>
		<CertificateStore>All</CertificateStore>
		<CertificateStoreMac>All</CertificateStoreMac>
		<CertificateStoreOverride>false</CertificateStoreOverride>
		<ProxySettings>Native</ProxySettings>
		<AllowLocalProxyConnections>true</AllowLocalProxyConnections>
		<AuthenticationTimeout>60</AuthenticationTimeout>
		<AutoConnectOnStart UserControllable="true">false</AutoConnectOnStart>
		<MinimizeOnConnect UserControllable="true">true</MinimizeOnConnect>
		<LocalLanAccess UserControllable="true">true</LocalLanAccess>
		<DisableCaptivePortalDetection UserControllable="true">false</DisableCaptivePortalDetection>
		<ClearSmartcardPin UserControllable="true">true</ClearSmartcardPin>
		<IPProtocolSupport>IPv4,IPv6</IPProtocolSupport>
		<AutoReconnect UserControllable="false">true
			<AutoReconnectBehavior UserControllable="false">DisconnectOnSuspend</AutoReconnectBehavior>
		</AutoReconnect>
		<AutoUpdate UserControllable="false">true</AutoUpdate>
		<RSASecurIDIntegration UserControllable="false">Automatic</RSASecurIDIntegration>
		<WindowsLogonEnforcement>SingleLocalLogon</WindowsLogonEnforcement>
		<WindowsVPNEstablishment>LocalUsersOnly</WindowsVPNEstablishment>
		<AutomaticVPNPolicy>false</AutomaticVPNPolicy>
		<PPPExclusion UserControllable="false">Disable
			<PPPExclusionServerIP UserControllable="false"></PPPExclusionServerIP>
		</PPPExclusion>
		<EnableScripting UserControllable="false">false</EnableScripting>
		<EnableAutomaticServerSelection UserControllable="false">false
			<AutoServerSelectionImprovement>20</AutoServerSelectionImprovement>
			<AutoServerSelectionSuspendTime>4</AutoServerSelectionSuspendTime>
		</EnableAutomaticServerSelection>
		<RetainVpnOnLogoff>false
		</RetainVpnOnLogoff>
		<AllowManualHostInput>true</AllowManualHostInput>
	</ClientInitialization>
	<ServerList>
		<HostEntry>
			<HostName>Abu Dhabi - UAE</HostName>
			<HostAddress>vpn.abudhabi.nyu.edu</HostAddress>
		</HostEntry>
		<HostEntry>
			<HostName>New York - NYU-NET Traffic Only</HostName>
			<HostAddress>vpn.nyu.edu</HostAddress>
			<UserGroup>nyu-vpn-SPLIT-DUO</UserGroup>
		</HostEntry>
		<HostEntry>
			<HostName>New York - All Traffic</HostName>
			<HostAddress>vpn.nyu.edu</HostAddress>
			<UserGroup>nyu-vpn-FULL-DUO</UserGroup>
		</HostEntry>
		<HostEntry>
			<HostName>Shanghai - Outside China</HostName>
			<HostAddress>vpn.shanghai.nyu.edu</HostAddress>
		</HostEntry>
		<HostEntry>
			<HostName>Shanghai - Inside China</HostName>
			<HostAddress>vpn-gnd.shanghai.nyu.edu</HostAddress>
		</HostEntry>
	</ServerList>
</AnyConnectProfile>
XML_EOF
}

write_profile
echo "Profile written to $PROFILE"
EOF

sudo chmod +x "$WATCHDOG_BIN"
echo "[+] Watchdog script installed at $WATCHDOG_BIN"

# --------------------------
# 2. Install LaunchDaemon
# --------------------------

print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root. Use: sudo $0"
    exit 1
fi

# Create the monitor script
print_status "Creating network monitor script..."

cat > /usr/local/bin/network_monitor.sh << 'EOF'
#!/bin/bash

# Network Change Monitor
# Executes $tempest on network changes

tempest="/usr/local/bin/ip-watchdog.sh"
LOG_FILE="/var/log/network_monitor.log"

get_network_state() {
    interfaces=$(ifconfig | grep -E "^(en|wl|utun)" | grep -c "status: active" 2>/dev/null || echo "0")
    ips=$(ifconfig | grep -E "inet " | grep -v 127.0.0.1 | wc -l | tr -d ' ')
    echo "${interfaces}-${ips}"
}

# Create log file
touch "$LOG_FILE"
echo "$(date): Network monitor started" >> "$LOG_FILE"

previous_state=$(get_network_state)

while true; do
    current_state=$(get_network_state)
    
    if [ "$current_state" != "$previous_state" ]; then
        echo "$(date): Network change detected" >> "$LOG_FILE"
        
        # Execute $tempest with sudo if it exists and is executable
        if [ -f "$tempest" ] && [ -x "$tempest" ]; then
            echo "$(date): Executing $tempest" >> "$LOG_FILE"
            /bin/bash $tempest >> "$LOG_FILE" 2>&1 &
        else
            echo "$(date): $tempest not found or not executable" >> "$LOG_FILE"
        fi
        
        previous_state=$current_state
    fi
    
    sleep 5
done
EOF

# Make monitor script executable
chmod +x /usr/local/bin/network_monitor.sh
print_success "Monitor script created"

# Create LaunchDaemon
print_status "Creating LaunchDaemon..."

cat > /Library/LaunchDaemons/com.user.networkmonitor.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.networkmonitor</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/network_monitor.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/var/log/network_monitor.log</string>
    <key>StandardErrorPath</key>
    <string>/var/log/network_monitor.log</string>
</dict>
</plist>
EOF

# Set LaunchDaemon permissions
chown root:wheel /Library/LaunchDaemons/com.user.networkmonitor.plist
chmod 644 /Library/LaunchDaemons/com.user.networkmonitor.plist
print_success "LaunchDaemon created"

# Load and start the service
print_status "Starting network monitor service..."

launchctl unload /Library/LaunchDaemons/com.user.networkmonitor.plist 2>/dev/null || true
launchctl load /Library/LaunchDaemons/com.user.networkmonitor.plist
launchctl start com.user.networkmonitor

# --------------------------
# 3. Patch AnyConnect profile for OnConnect hook
# --------------------------

copy_profile() {
    # execute the write_profile function from the watchdog script with privileges
    sudo /bin/bash "$WATCHDOG_BIN"
}

if [[ -f "$PROFILE" ]]; then
    if ! grep -q "Outside" "$PROFILE"; then
        copy_profile
        echo "[+] OnConnect/OnDisconnect hooks added to $PROFILE"
    else
        echo "[*] Hooks already present, skipping patch"
    fi
else
    echo "[!] AnyConnect profile not found at $PROFILE, re-adding patch"
    copy_profile
fi

echo "[✓] AnyConnect IP Watchdog installation complete"

print_success "Network monitor installed and started!"
echo ""
print_status "The monitor will:"
echo "  - Run automatically in the background"
echo "  - Start on system boot"
echo "  - Execute $tempest when network changes are detected"
echo "  - Log activities to /var/log/network_monitor.log"
echo ""
print_status "Create $tempest with your custom commands:"
echo "  sudo nano $tempest"
echo "  sudo chmod +x $tempest"
echo ""
print_status "Check logs with: tail -f /var/log/network_monitor.log"

