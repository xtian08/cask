#!/bin/bash

# Set up variables and functions here
consoleuser=$(stat -f "%Su" /dev/console)
echo "Console user is $consoleuser"
aMU_PASSWD="1234"

# Generate sap.sh in /Users/Shared
echo "Generating sap.sh"
echo -e "#!/bin/bash\n\necho \"$aMU_PASSWD\"" > /tmp/sap.sh
chmod +x /tmp/sap.sh

# Set the SUDO_ASKPASS environment variable to the newly created script
export SUDO_ASKPASS="/tmp/sap.sh"

echo "Installing Managed Apps"
# Path to Homebrew
export HOMEBREW_NO_SANDBOX=1

# Define user and UID
mUSER="itops"
uid=$(id -u $USER 2>/dev/null)
GROUP="staff"

sudo -A -E -H -u "#$uid" env HOME="/Users/$mUSER" bash -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'

# Final cleanup
rm -f /tmp/sap.sh
unset SUDO_ASKPASS
unset HOMEBREW_NO_SANDBOX

echo >> /Users/$mUSER/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/$mUSER/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
