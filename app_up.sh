######################################################################
####################################################
#!/bin/bash
# Description: Update Managed APPS
# Version: 0.1
# Author: Chris Mariano
# Tests: Tested on macOS 15 (ARM and Intel).
####################################################

app_up='    "/Applications/Firefox.app,firefox,2"'

###################################
echo "---------------------"
echo "#############Checking App Updater#############"
echo "---------------------"
###################################
echo "Checking Command Line Tools for Xcode..."

# Function to check if CLT is installed
is_clt_installed() {
  xcode-select -p &> /dev/null
  return $?
}

# Only install if not already installed
if ! is_clt_installed; then
  echo "Command Line Tools not found. Starting installation..."

  # Trigger softwareupdate to list CLT
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

  # Try up to 3 times
  retries=3
  count=0
  success=0

  while [ $count -lt $retries ]; do
    echo "Attempt $(($count + 1)) of $retries..."

    # Get the product name again (in case list changes)
    PROD=$(softwareupdate -l | grep "\*.*Command Line" | tail -n 1 | sed 's/^[^C]* //')

    if [ -z "$PROD" ]; then
      echo "No Command Line Tools update found in softwareupdate output."
      break
    fi

    # Try to install
    softwareupdate -i "$PROD" --verbose

    # Check result
    if is_clt_installed; then
      echo "Command Line Tools successfully installed."
      success=1
      break
    else
      echo "Installation failed. Retrying in 10 seconds..."
      sleep 10
    fi

    count=$((count + 1))
  done

  # Clean up trigger file
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

  # Final status
  if [ $success -ne 1 ]; then
    echo "Command Line Tools installation failed after $retries attempts."
  fi
else
  echo "Command Line Tools already installed."
fi

###################################

# Check Brew and start logging
echo "Homebrew Installation"

# Set up variables and functions here
consoleuser=$(stat -f "%Su" /dev/console)
echo "Console user is $consoleuser"
UNAME_MACHINE="$(uname -m)"

# Set the prefix based on the machine type
if [[ "$UNAME_MACHINE" == "arm64" ]]; then
    # M1/arm64 machines
    brew_prefix="/opt/homebrew"
else
    # Intel machines
    brew_prefix="/usr/local"
fi

#Function to install Homebrew
install_homebrew() {

    # are we in the right group
    check_grp=$(groups ${consoleuser} | grep -c '_developer')
    if [[ $check_grp != 1 ]]; then
        /usr/sbin/dseditgroup -o edit -a "${consoleuser}" -t user _developer
        chown -R "${consoleuser}":_developer ${brew_prefix}/Cellar 
    fi

    # Have the xcode command line tools been installed?
    echo "Checking for Xcode Command Line Tools installation"
    check=$( pkgutil --pkgs | grep -c "CLTools_Executables" )

    if [[ "$check" != 1 ]]; then
        echo "Installing Xcode Command Tools"
        # This temporary file prompts the 'softwareupdate' utility to list the Command Line Tools
        touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        clt=$(softwareupdate -l | grep -B 1 -E "Command Line (Developer|Tools)" | awk -F"*" '/^ +\*/ {print $2}' | sed 's/^ *//' | tail -n1)
        # the above don't work in Catalina so ...
        if [[ -z $clt ]]; then
            clt=$(softwareupdate -l | grep  "Label: Command" | tail -1 | sed 's#* Label: (.*)#1#')
        fi
        softwareupdate -i "$clt"
        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        /usr/bin/xcode-select --switch /Library/Developer/CommandLineTools
    fi
    echo "Xcode Command Line Tools installed"

    # Is homebrew already installed?
    if [[ ! -e ${brew_prefix}/bin/brew ]]; then
        # Install Homebrew. This doesn't like being run as root so we must do this manually.
        echo "Installing Homebrew"

        mkdir -p ${brew_prefix}/Homebrew
        # Curl down the latest tarball and install to ${brew_prefix}
        curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C ${brew_prefix}/Homebrew

        # Manually make all the appropriate directories and set permissions
        mkdir -p ${brew_prefix}/Cellar ${brew_prefix}/Homebrew
        mkdir -p ${brew_prefix}/Caskroom ${brew_prefix}/Frameworks ${brew_prefix}/bin
        mkdir -p ${brew_prefix}/include ${brew_prefix}/lib ${brew_prefix}/opt ${brew_prefix}/etc ${brew_prefix}/sbin
        mkdir -p ${brew_prefix}/share/zsh/site-functions ${brew_prefix}/var
        mkdir -p ${brew_prefix}/share/doc ${brew_prefix}/man/man1 ${brew_prefix}/share/man/man1
        chown -R "${consoleuser}":_developer ${brew_prefix}/*
        chmod -R g+rwx ${brew_prefix}/*
        chmod 755 ${brew_prefix}/share/zsh ${brew_prefix}/share/zsh/site-functions

        # Create a system wide cache folder  
        mkdir -p /Library/Caches/Homebrew
        chmod g+rwx /Library/Caches/Homebrew
        chown "${consoleuser}:_developer" /Library/Caches/Homebrew

        # put brew where we can find it
        ln -s ${brew_prefix}/Homebrew/bin/brew ${brew_prefix}/bin/brew
    fi
}

# Make sure brew is up to date
install_homebrew
echo "Homebrew installation complete"

echo "Clearing mds.install.lock and restarting installd process..."
sudo rm -f /private/var/db/mds/system/mds.install.lock
sudo killall -1 installd

###################################
# Add Zoom IT configuration plist
# Get latest Zoom version

# Get latest Zoom version
cask_json="zoom.json"
latest_json=$(curl -s "https://formulae.brew.sh/api/cask/$cask_json")
sap_test="!!c0usc0us25//"
latestver=$(echo "$latest_json" | grep -o '"version":"[^"]*"' | awk -F'"' '{print $4}')
echo "Latest Version is: $latestver"

# Define plist path
plist_path="/opt/homebrew/Caskroom/zoom-for-it-admins/${latestver}/us.zoom.config.plist"

# Create directory if it doesn't exist
sudo mkdir -p "$(dirname "$plist_path")"

# Check if plist exists and notify
if [ -f "$plist_path" ]; then
    echo "Plist exists at $plist_path — it will be overwritten."
else
    echo "Plist does not exist at $plist_path — it will be created."
fi

# Write plist with sudo privileges
sudo tee "$plist_path" > /dev/null <<EOF
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

###################################
# Set up variables and functions here
consoleuser=$(stat -f "%Su" /dev/console)
echo "Console user is $consoleuser"

# Generate sap.sh in /Users/Shared
echo "Generating sap.sh"
echo -e "#!/bin/bash\n\necho \"$sap_test\"" > /tmp/sap.sh
chmod +x /tmp/sap.sh

# Set the SUDO_ASKPASS environment variable to the newly created script
export SUDO_ASKPASS="/tmp/sap.sh"

echo "Installing Managed Apps"
# Path to Homebrew
export HOMEBREW_NO_SANDBOX=1

# Define app list (supports exact and wildcard paths)
# 0/1/2 marker logic for conditional behavior (skip, install/update, kill if running before update)
app_list=(
    $app_up
)

#Identify itops UID
uid=$(id -u itops)

echo "itops user found with UID $uid"
# Create the user's home directory if it doesn't exist
if [ ! -d "/Users/itops" ]; then
    sudo mkdir -p /Users/itops
fi

# Move to a safe directory to avoid permission errors
cd /tmp

# Define user and UID
USER="itops"
uid=$(id -u $USER 2>/dev/null)
GROUP="staff"

# Detect machine architecture and set Homebrew prefix
UNAME_MACHINE=$(uname -m)
if [[ "$UNAME_MACHINE" == "arm64" ]]; then
    brew_prefix="/opt/homebrew"  # M1/M2 (Apple Silicon)
else
    brew_prefix="/usr/local"  # Intel Macs
fi

brew_path=$(
	{ [ -x /opt/homebrew/bin/brew ] && echo "arch -arm64 /opt/homebrew/bin/brew"; \
	[ -x /usr/local/bin/brew ] && echo "arch -x86_64 /usr/local/bin/brew"; } | head -1
)
echo "$brew_path"

# Create required directories
sudo mkdir -p /var/itops/Library/Caches/Homebrew /Users/itops/Library/Caches \
$brew_prefix $brew_prefix/{Cellar,Frameworks,bin,etc,include,opt,sbin,lib,share,share/aclocal,share/doc,share/info,share/locale,share/man/man{1,3,5,7,8},share/zsh/site-functions,var/log,Caskroom} >/dev/null 2>&1

# Change ownership
sudo chown -R $USER:$GROUP /Users/itops /var/itops/Library/Caches/Homebrew /Users/itops/Library/Caches >/dev/null 2>&1
sudo chown -R $(id -un $uid):$(id -gn $uid) $brew_prefix/{Homebrew,var/homebrew,etc/bash_completion.d,Cellar,Frameworks,bin,etc,include,opt,sbin,lib,share,share/zsh/site-functions,var/log,Caskroom} >/dev/null 2>&1

# Ensure /opt/homebrew is owned by 'itops'
sudo chown -R itops /opt/homebrew >/dev/null 2>&1

# Set permissions
sudo chmod -R u+rw $brew_prefix/{Homebrew,var/homebrew,Cellar,Frameworks,bin,etc,include,opt,sbin,Caskroom} >/dev/null 2>&1
sudo chmod -R u+rw /var/itops/Library/Caches/Homebrew /Users/itops/Library/Caches >/dev/null 2>&1
sudo chmod -R u+rwx $brew_prefix >/dev/null 2>&1
sudo chmod u+w /opt/homebrew >/dev/null 2>&1

echo "---------------------"
echo "############# Performing App Updates #############"
echo "---------------------"

for entry in "${app_list[@]}"; do
    raw_path="${entry%%,*}"
    cask_part="${entry#*,}"
    cask_name="${cask_part%%,*}"
    behavior="${entry##*,}"

    # Expand wildcard paths safely
    IFS=$'\n' read -rd '' -a app_paths <<< "$(compgen -G "$raw_path")"

    if [ "${#app_paths[@]}" -eq 0 ]; then
        if [[ "$behavior" -eq 0 ]]; then
            echo "Skipping $cask_name: $raw_path not found."
            continue
        fi
    fi

    # Skip logic based on behavior
    if [[ "$behavior" -eq 1 ]]; then
        for app_path in "${app_paths[@]}"; do
            app_name="$(basename "$app_path" .app)"
            if pgrep -f "$app_name" > /dev/null; then
                echo "Skipping $cask_name: $app_name is currently running."
                continue 2
            fi
        done
    elif [[ "$behavior" -eq 2 ]]; then
        for app_path in "${app_paths[@]}"; do
            app_name="$(basename "$app_path" .app)"
            if pgrep -f "$app_name" > /dev/null; then
                echo "Killing $app_name before updating $cask_name..."
                pkill -f "$app_name"
            fi
        done
    fi

    echo "Installing/updating $cask_name..."
    sudo -A -E -H -u "#$uid" env HOME="/Users/itops" bash -c "$brew_path install --cask --verbose --adopt '$cask_name'" 2>&1
    echo "Install process done for $cask_name"

done

sudo rm -f /tmp/sap.sh
unset SUDO_ASKPASS
unset HOMEBREW_NO_SANDBOX

echo "---------------------"
echo "Cask App List"
$brew_path list --cask
echo "---------------------"
