#!/bin/bash
# Author: Chris Mariano
# Date: 2023-10-03
# Description: This script installs the latest version of SwiftDialog and run MacOS updates.

###################################
# SwiftDialog Install

#!/bin/bash

LOG_FILE="/var/log/mandatory_os_upgrade.log"

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
echo "[$(date)] Starting erase-install in test-run mode..."
curl -s https://raw.githubusercontent.com/xtian08/cask/master/erase-install-swift.sh | sudo zsh /dev/stdin \
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
  --test-run

echo "[$(date)] erase-install completed (test-run)."
