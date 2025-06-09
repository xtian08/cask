#!/bin/bash
# Author: Chris Mariano
# Date: 2023-10-03
# Description: This script installs the latest version of SwiftDialog and run MacOS updates.

###################################
# SwiftDialog Install

#!/bin/bash

TEST_RUN=0
VERSION_CHECK=1

if [[ "$VERSION_CHECK" = 1 ]]; then

    # Get sw_vers -productVersion
    mac_version=$(sw_vers -productVersion)
    echo "Installed Version: $mac_version"

    # Fetch the HTML content and extract version numbers and OS names
    curl -s https://support.apple.com/en-ae/109033 | \
    grep -o '<div class="table-wrapper gb-table">.*</div>' | \
    awk -F'<tr>' '{for(i=2; i<=NF; i++) {gsub(/<\/?(p|th|td|tr)[^>]*>/,"",$i); if($i ~ /macOS/) print $i; else printf "%s\n", $i}}' | \
    sudo tee /tmp/apple_versions_and_names.txt | \
    sudo grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' > /tmp/apple_versions.txt

    # Get the latest version and its corresponding OS name
    latest_version=$(cat /tmp/apple_versions_and_names.txt | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    latest_os_name=$(cat /tmp/apple_versions_and_names.txt | grep -Eo 'macOS [A-Za-z]+' | head -n 1)

    # Extract the major version from the latest version (e.g., "15" from "15.1")
    major_version=$(echo $latest_version | cut -d'.' -f1)
    echo "Latest macOS version: $latest_version"
    sudo rm /tmp/apple_versions.txt
    sudo rm /tmp/apple_versions_and_names.txt

    # Check if the installed version is less than the latest version
    if [[ $(echo "$mac_version < $latest_version" | bc) -eq 1 ]]; then
        echo "[$(date)] Your Mac is running an outdated OS: $mac_version. Latest version is $latest_version."
    else
        echo "[$(date)] Your Mac is up to date: $mac_version."
        exit 0
    fi

fi

LOG_FILE="/var/log/ws1-mxupgrade.log"

exec > >(sudo tee -a "$LOG_FILE" | logger -t MandatoryOSUpgrade) 2>&1


echo "[$(date)] Starting Mandatory OS Upgrade Script..."

SWIFT_DIALOG_PATH="/usr/local/bin/dialog"
SWIFT_DIALOG_PKG="/tmp/dialog.pkg"

if [[ ! -x "$SWIFT_DIALOG_PATH" ]]; then
    echo "[$(date)] SwiftDialog not found. Downloading and installing..."
    url=$(curl -s https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest |
            grep 'browser_download_url.*dialog-.*pkg' | grep -v 'launcher' | awk -F '"' '{print $4}')
    if [[ -n "$url" ]]; then
        echo "[$(date)] Downloading from $url"
        curl -L "$url" -o "$SWIFT_DIALOG_PKG"
        sudo installer -pkg "$SWIFT_DIALOG_PKG" -target /
        echo "[$(date)] SwiftDialog installed."
    else
        echo "[$(date)] Failed to retrieve SwiftDialog download URL."
        exit 1
    fi
else
    echo "[$(date)] SwiftDialog already installed."
fi

# Get logged in user's full name
logged_in_user=$(stat -f "%Su" /dev/console)
full_name=$(dscl . -read /Users/"$logged_in_user" RealName 2>/dev/null | awk 'NR==1 {if ($0 ~ /^RealName:/ && NF > 1) {print $2; exit}} NR > 1 {print; exit}' | xargs)
echo "[$(date)] Logged in user: $logged_in_user, Full name: $full_name"

# Display dialog
response=$("$SWIFT_DIALOG_PATH" \
    --title "MacOS Upgrade Upgrade Required" \
    --message "Dear $full_name\n\nYour Mac is running an outdated OS.\n\nTo upgrade: Click on **Proceed**.\n\n☞ Enter your Mac Password when prompted.\n\n☞ Save your work before the update starts.\n\n**Need Help?** Email us email:nyuad.it@nyu.edu or Campus Line: x88888" \
    --icon caution \
    --overlayicon https://raw.githubusercontent.com/xtian08/cask/refs/heads/main/NYUADLogobox.png \
    --iconsize 300 \
    --button1text "Proceed" \
    --blurscreen \
    --ontop \
    --timeout 60 \
    --json)

echo "[$(date)] User response: $response"

# Begin erase-install (test-run)

echo "[$(date)] Starting erase-install in $( [ "$TEST_RUN" = true ] && echo "test-run" || echo "live" ) mode..."
curl -s https://raw.githubusercontent.com/xtian08/cask/master/erase-install-swift.sh | sudo bash \
  --reinstall \
  --update \
  --depnotify \
  --min-drive-space=35 \
  --no-fs \
  --rebootdelay 300 \
  --check-power \
  --power-wait-limit 600 \
  --max-password-attempts infinite \
  --current-user \
  --no-jamfhelper \
  --no-timeout \
  $( [ "$TEST_RUN" = 1 ] && echo "--test-run" )

echo "[$(date)] erase-install completed ($([ "$TEST_RUN" = true ] && echo "test-run" || echo "live"))."
