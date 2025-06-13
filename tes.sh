#!/bin/bash
# Created by Chris Mariano

####################################################
# Description: OS Upgrader
# Version: 2.0
# Author: Chris Mariano
# Tests: Tested on macOS 15 (ARM and Intel).
####################################################

# Variables
start_date_file="/Users/shared/muufile.txt"
defer_days="5"
delay_days=0
CNlist=("name1" "ADUAEI15736LPMX" "xTianm4mAx1") #Excluded for major
ARCH=$(uname -m)

#Simulate other version
SIMS=0

if [[ "$SIMS" = 1 ]]; then
    echo "####################################################################"
    echo "####################### Simulating is ACTIVE #######################"    #Simulation Variables
    echo "####################################################################"
    SIMS_mac_version="13.16.1" #local installed version
    SIMS_os_list="15.5\n15.4.1\n15.4\n15.3.2\n15.3.1\n12.7.6" #Available versions
    SIMS_os_list="13.20"
    SIMS_major_version="15" #cloud major version
    ddb="yes" #Release date is more than delay days ago
    #ARCH="x86_64" #Architecture
fi

echo "*************Checking MacOS SU*************"

echo "####################################################################"
echo $(date) + "Performing Software Update Check for macOS"
echo "####################################################################"

# Function to get all active network services
get_active_service() {
    # List all network services, skip the first line, and check for active ones
    networksetup -listallnetworkservices | tail -n +2 | while read -r service; do
        STATUS=$(networksetup -getinfo "$service" 2>/dev/null | grep -i "IP address" | grep -v "none")
        if [[ -n "$STATUS" ]]; then
            echo "$service"
            return
        fi
    done
}

# Uninstall BloXOne app if installed
uninstall_bloxone() {
    BLOXONE_PATH="/Applications/Infoblox/BloxOne Endpoint.app"
    if [ -d "$BLOXONE_PATH" ]; then
        echo "BloXOne app found. Uninstalling..."
        sudo sh /Applications/Infoblox/Uninstall\ BloxOne\ Endpoint.app/Contents/Resources/ib_rc_uninstall.sh --delete_app_data
        echo "BloXOne app uninstalled."
    else
        echo "BloXOne app not found. Skipping uninstallation."
    fi
}

# Get the active primary network service
ACTIVE_SERVICE=$(get_active_service)

if [ -z "$ACTIVE_SERVICE" ]; then
    echo "No active network service detected."
fi

# Get the current DNS servers
CURRENT_DNS=$(networksetup -getdnsservers "$ACTIVE_SERVICE" 2>/dev/null)

# Echo the current DNS
echo "Active net: $ACTIVE_SERVICE"
if [[ "$CURRENT_DNS" == "There aren't any DNS Servers set on"* ]]; then
    echo "With DNS: NONE"
else
    echo "With DNS: $CURRENT_DNS"
fi

check_dns() {
    # Check if DNS starts with 127.0
    if echo "$CURRENT_DNS" | grep -q "^127\.0"; then
        echo "DNS starts with 127.0, setting DNS to DHCP (automatic)..."
        echo "Skipped Blox1" #uninstall_bloxone
        sudo networksetup -setdnsservers "$ACTIVE_SERVICE" "Empty"
        echo "DNS set to automatic."
    else
        echo "DNS does not start with 127.0, no changes made."
    fi
}

if [[ "$SIMS" = 0 ]]; then

    # Check if the start date file exists
    if [ ! -f "$start_date_file" ]; then
        # If the file doesn't exist, create it and write the current date
        date +%s > "$start_date_file"
    fi

    # Read the start date from the file
    start_date=$(cat "$start_date_file")

    # Fetch the HTML content and extract version numbers and OS names
    curl -s https://support.apple.com/en-ae/109033 | \
    grep -o '<div class="table-wrapper gb-table">.*</div>' | \
    awk -F'<tr>' '{for(i=2; i<=NF; i++) {gsub(/<\/?(p|th|td|tr)[^>]*>/,"",$i); if($i ~ /macOS/) print $i; else printf "%s\n", $i}}' | \
    tee /tmp/apple_versions_and_names.txt | \
    grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' > /tmp/apple_versions.txt

    # Get the latest version and its corresponding OS name
    latest_version=$(cat /tmp/apple_versions_and_names.txt | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1)
    latest_os_name=$(cat /tmp/apple_versions_and_names.txt | grep -Eo 'macOS [A-Za-z]+' | head -n 1)

    # Extract the major version from the latest version (e.g., "15" from "15.1")
    major_version=$(echo $latest_version | cut -d'.' -f1)
    Current_BaseOS="$latest_os_name $major_version"
    Current_FullOS="$latest_os_name $latest_version"
    echo "~~~~~~"

    # Fetch the HTML content from the target page
    secURL="https://support.apple.com"
    html_content=$(curl -s $secURL/en-ae/100100)
    href=$(echo "$html_content" | \
    grep -o "<a href=\"[^\"]*\" class=\"gb-anchor\">$Current_BaseOS</a>" | \
    sed -E 's/.*href="([^"]+)".*/\1/')

    FullOSurl=$secURL$href
    #echo "Current OS URL: $FullOSurl"

    # Fetch the release date from the FullOSurl page using sed
    release_date=$(curl -s $FullOSurl | sed -n 's/.*<div class="note gb-note"><p class="gb-paragraph">Released \([^<]*\)<\/p><\/div>.*/\1/p')

    # Convert the release date to Unix timestamp
    release_timestamp=$(date -j -f "%B %d, %Y" "$release_date" +%s)

    # Get the current date in Unix timestamp format
    current_timestamp=$(date +%s)

    # Calculate the difference in days
    days_diff=$(( (current_timestamp - release_timestamp) / 86400 ))
    echo "$Current_BaseOS released on $release_date and its been $days_diff days"
    if [ $days_diff -gt $delay_days ]; then ddb="yes"; else ddb="no"; fi
    #echo "Is the release date more than $delay_days days? $ddb"

    # Fetch the HTML content from the target page
    secURL="https://support.apple.com"
    html_content=$(curl -s $secURL/en-ae/100100)
    href=$(echo "$html_content" | \
    grep -o "<a href=\"[^\"]*\" class=\"gb-anchor\">$Current_FullOS</a>" | \
    sed -E 's/.*href="([^"]+)".*/\1/')

    FullOSurl=$secURL$href
    # Fetch the release date from the FullOSurl page using sed
    release_date_min=$(curl -s $FullOSurl | sed -n 's/.*<div class="note gb-note"><p class="gb-paragraph">Released \([^<]*\)<\/p><\/div>.*/\1/p')

    # Convert the release date to Unix timestamp
    release_timestamp_min=$(date -j -f "%B %d, %Y" "$release_date_min" +%s)

    # Get the current date in Unix timestamp format
    current_timestamp_min=$(date +%s)

    # Calculate the difference in days
    days_diff=$(( (current_timestamp_min - release_timestamp_min) / 86400 ))
    echo "$Current_FullOS released on $release_date_min and its been $days_diff days"
    if [ $days_diff -gt $delay_days ]; then ddb="yes"; else ddb="no"; fi
    #echo "Is the release date more than $delay_days days? $ddb"
else
    echo "~~~~~~"
    echo "Skipping fetching of Apple versions and release dates due to SIMS mode."
    major_version=$SIMS_major_version
fi
echo "~~~~~~"

# Get sw_vers -productVersion
if [[ "$SIMS" = 0 ]]; then
    mac_version=$(sw_vers -productVersion)
else
    mac_version=$SIMS_mac_version
fi
# Extract mac_major version
major_mac=$(echo "$mac_version" | cut -d '.' -f 1)
minor_mac=$(echo "$mac_version" | cut -d '.' -f 2)
sub_minor_mac=$(echo "$mac_version" | cut -d '.' -f 3)
if [ -z "$sub_minor_mac" ]; then
    sub_minor_mac="0"
fi

# Find the corresponding version in the list
version=$(grep "^$major_mac\." /tmp/apple_versions.txt)


# Check if version exists
if [ -n "$version" ]; then
    echo "Installed Version: $mac_version with available build $version"
else
    echo "Installed Version: $mac_version with no available build"
fi

# Extract major version from the version
major=$(echo "$version" | cut -d '.' -f 1)
minor=$(echo "$version" | cut -d '.' -f 2)
sub_minor=$(echo "$version" | cut -d '.' -f 3)
if [ -z "$sub_minor" ]; then
    sub_minor="0"
fi

# Fetch latest OS versions - command is different for macOS 14.0 and later
if [[ "$SIMS" = 0 ]]; then
    if [[ "$mac_version" < "14.0" ]]; then
        os_list=$(softwareupdate -lr --os-only | awk -F 'Version: |, Size' '/Title:/{print $2}')
    else
        os_list=$(softwareupdate --list-full-installers | awk -F 'Version: |, Size' '/Title:/{print $2}')
    fi
else
    os_list=$(echo -e "$SIMS_os_list")
fi

sorted_os_list=$(sort -r --version-sort <<<"$os_list")
sorted_os_list_n1=$(echo "$sorted_os_list" | grep -v '^'$major_version'')
hori_list=$(echo "$sorted_os_list" | tr '\n' ' ')
echo "List of available version: $hori_list"
highest_version=$(echo "$sorted_os_list" | head -n 1)
Cname=$(scutil --get ComputerName)
SNum=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')

# Extract highest_version version
major_now=$(echo "$highest_version" | cut -d '.' -f 1)
minor_now=$(echo "$highest_version" | cut -d '.' -f 2)
sub_minor_now=$(echo "$highest_version" | cut -d '.' -f 3)
if [ -z "$sub_minor_now" ]; then
    sub_minor_now="0"
fi
echo "~~~~~~"
#Check if the release date is more than delay days ago
if [[ " ${CNlist[@]} " =~ " ${Cname} " ]]; then #Check if CN is in the exclusion list
    highest_version="$version"
    echo "Device is excluded for major upgrade"
    echo "Highest version available1: $highest_version"
    ##>>>> Check OK - default is CNlist
elif [ $major_version == $major_mac ]; then #Check minor update for current version
    echo "Device is on the latest major version"
    highest_version="$version"
    echo "Highest version available2: $highest_version"
    ##>>>> Check OK - default is major_version
elif [ "$ddb" == "no" ]; then #Check if the release date is more than delay days ago
    echo "Release date is not more than $delay_days days ago"
    highest_version=$(echo "$sorted_os_list_n1" | head -n 1)
    echo "Highest version available3: $highest_version"
    ##>>>> Check OK - default is ddb
elif [ "$ARCH" == "arm64" ]; then #ARM measns always latest version
    echo "Highest version available4: $highest_version"
    ##>>>> Check OK - default is ARM64
elif [ $major_mac -ge $major_version ]; then
    echo "Highest version available5: $highest_version"
    ##>>>> Check OK - default is major_mac
else
    highest_version=""
    echo "Highest version not unavailable"
fi

# If SU result is empty, set static value
if [ -z "$highest_version" ]; then
    # Check if the release date is more than delay days ago
    if [ "$ddb" == "yes" ]; then
        major=$((major_version))
        echo "Allowed OS is $major (static)1"
    elif [ $major_mac -lt $major_version ]; then
        echo "Allowed OS is $major (static)2"
    else
        if [ "$ddb" == "yes" ]; then
        major=$((major_version))
        echo "Allowed OS is $major (static)3"
        else
        major=$((major - 1))
        echo "Allowed OS is $major (static)4"
        fi
    fi
    version=$(grep "^$major\." /tmp/apple_versions.txt)
    highest_version=$version
    echo "Highest version available: $highest_version"
fi


if [ $major_mac -lt $(($major_version - 2)) ]; then
    # If macOS version is less than 12.0, mark as EOL
    echo "EOL"
    sudo rm "$start_date_file"
    exit 0
elif (($major_mac >= $major_now && $minor_mac >= $minor_now && $sub_minor_mac >= $sub_minor_now)); then
    # If macOS version is up to date, mark as Compliant
    echo "Compliant 1. No action required."
    sudo rm "$start_date_file"
    exit 0
elif [[ "$major_mac" -eq "$major_now" && ( "$minor_mac" -ne "$minor_now" || "$sub_minor_mac" -ne "$sub_minor_now" ) ]]; then
    # If major version is equal but minor or sub-minor version is not equal, echo test
    echo "Performing Minor Update ONLY!"
    sudo /usr/local/bin/hubcli mdmcommand --osupdate --productversion "$highest_version" --installaction InstallForceRestart --priority high --maxuserdeferrals 3
    exit 0
else
    # If macOS version is outdated, notify user to upgrade
    current_date=$(date +%s)
    elapsed_days=$(( (current_date - start_date) / 86400 ))  # Calculate elapsed days
    remaining_days=$((defer_days - elapsed_days))  # Calculate remaining days

    if [[ "$(printf '%s\n' "$highest_version" "$mac_version" | sort -V | tail -n1)" == "$mac_version" ]]; then
	    echo "Compliant 2. No action required."
	    sudo rm "$start_date_file"
	    echo "****** macOS SU check completed ******"
	    exit 0
    fi


    if [ $elapsed_days -ge $defer_days ]; then
        echo "Forced_Update to $highest_version"
        check_dns
        sudo /usr/local/bin/hubcli notify \
        -t "NYUAD Mandatory macOS Upgrade" \
        -s "$defer_days days deferral had elapsed." \
        -i "Update to "$highest_version" is being applied on your machines, it will restart automatically once completed. The installation will take up to 30-40 Min and will be notified for reboot."
        sudo /usr/local/bin/hubcli mdmcommand --osupdate --productversion "$highest_version" --installaction InstallASAP
    elif [ $remaining_days -eq 1 ]; then
        defer_end_timestamp=$((start_date + defer_days * 86400))
        defer_end_datetime=$(date -r "$defer_end_timestamp" "+%b %d %I:%M%p")
        echo "Last day warn to $highest_version at $defer_end_datetime."
        check_dns
        # Defer option notify
        sudo /usr/local/bin/hubcli notify \
        -t "Gentle Reminder" \
        -s "NYUAD MACOS Update to $highest_version" \
        -i "Your macOS is now scheduled for an automatic upgrade on $defer_end_datetime." \
        -a "Start update now" \
        -b "sudo /usr/local/bin/hubcli mdmcommand --osupdate --productversion "$highest_version" --installaction InstallASAP" \
        -c "Acknowledge this alert"
    else
        echo "Notify_Update to $highest_version"
        check_dns
        # Defer option notify
        sudo /usr/local/bin/hubcli notify \
        -t "NYUAD MACOS Update to $highest_version" \
        -s "" \
        -i "Update now to begin. Once installed, you will be notified to restart your computer. The restart may take up to 30 min. You have $remaining_days days remaining to defer this update." \
        -a "Start update now" \
        -b "sudo /usr/local/bin/hubcli mdmcommand --osupdate --productversion "$highest_version" --installaction InstallASAP" \
        -c "Do this later"
    fi
fi

echo "****** macOS SU check completed ******"
