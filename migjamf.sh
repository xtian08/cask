#!/bin/bash

## check run settings for arguments

## get macOS version
macOS_Version=$(sw_vers -productVersion)
majorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $1}' )
minorVer=$( /bin/echo "$macOS_Version" | /usr/bin/awk -F. '{print $2}' )

## account with computer create and read (JSS Objects), Send Computer Unmanage Command (JSS Actions)
uname="apimdmremove"
pwd="!Welcome20"
server="https://nyuad.jamfcloud.com/"

## ensure the server URL ends with a /
strLen=$((${#server}-1))
lastChar="${server:$strLen:1}"
if [ ! "$lastChar" = "/" ];then
    server="${server}/"
fi

## get unique identifier for machine
udid=$(/usr/sbin/system_profiler SPHardwareDataType | awk '/UUID/ { print $3; }')
if [ "$udid" == "" ];then
    echo "unable to determine UUID of computer - exiting."
else
    echo "computer UUID: $udid"
fi

## get token
tokenURL="${server}api/v1/auth/token"
echo $tokenURL

clientString="grant_type=client_credentials&client_id=$uname&client_secret=$pwd"

response=$(curl -s -u "$uname":"$pwd" "$tokenURL" -X POST)
bearerToken=$(echo "$response" | plutil -extract token raw -)
echo "**************************"
echo "theToken: $bearerToken"
echo "**************************"


## get computer ID from Jamf server
echo "get computer ID: curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H \"Accept: application/xml\" -H \"Authorization: Bearer $(echo $bearerToken | head -n15)...\""
compXml=$(/usr/bin/curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H "Accept: application/xml" -H "Authorization: Bearer $bearerToken")
echo "**************************"
echo "computer record: ${compXml}"
echo "**************************"
