#!/bin/bash
#Created by Chris Mariano
#Description: Zoom Install Script

mkdir -p /tmp/zoom
cd /tmp/zoom || exit 1

# Get latest Zoom version
cask_json="zoom.json"
latest_json=$(curl -s "https://formulae.brew.sh/api/cask/$cask_json")
latestver=$(echo "$latest_json" | grep -o '"version":"[^"]*"' | awk -F'"' '{print $4}')
echo "Latest Version is: $latestver"

if pgrep -x "zoom.us" > /dev/null; then
    echo "Zoom is currently running. Exiting."
    exit 0
fi

# If installed, compare versions
if [ -d "/Applications/zoom.us.app" ]; then
    currentver=$(/usr/bin/defaults read /Applications/zoom.us.app/Contents/Info CFBundleVersion)
    echo "Installed version: $currentver"
    if [ "$currentver" = "$latestver" ]; then
        echo "Zoom is up to date. Exiting."
        exit 0
    else
        echo "Old version found. Forcing uninstall..."
        sudo rm -rf /Applications/zoom.us.app
    fi
else
    echo "Zoom not found. Proceeding with fresh install..."
fi

# Write Zoom configuration plist
cat <<EOF > /tmp/zoom/us.zoom.config.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Enable49Video</key><true/>
    <key>EnableEchoCancellation</key><true/>
    <key>LastLoginType</key><true/>
    <key>ZAutoFitWhenViewShare</key><true/>
    <key>ZAutoFullScreenWhenViewShare</key><true/>
    <key>ZAutoJoinVoip</key><true/>
    <key>ZAutoSSOLogin</key><true/>
    <key>ZAutoUpdate</key><true/>
    <key>ZDisableVideo</key><true/>
    <key>ZDualMonitorOn</key><true/>
    <key>ZRemoteControlAllApp</key><true/>
    <key>ZSSOHost</key><string>nyu.zoom.us</string>
    <key>ZUse720PByDefault</key><false/>
    <key>disableloginwithemail</key><false/>
    <key>enablehidcontrol</key><true/>
    <key>keepsignedin</key><true/>
    <key>nofacebook</key><true/>
    <key>nogoogle</key><true/>
    <key>EnableAppleLogin</key><false/>    
</dict>
</plist>
EOF

# Download and install Zoom
echo "Downloading Zoom version ${latestver}..."
curl -L -o zoom.pkg "https://cdn.zoom.us/prod/${latestver}/ZoomInstallerIT.pkg"
echo "Installing Zoom..."
sudo installer -allowUntrusted -pkg /tmp/zoom/zoom.pkg -target /

# Cleanup
rm -rf /tmp/zoom/
echo "Zoom installation complete."
