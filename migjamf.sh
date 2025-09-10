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
    exit 1
else
    echo "computer UUID: $udid"
fi

## get token
tokenURL="${server}api/oauth/token"

clientString="grant_type=client_credentials&client_id=$uname&client_secret=$pwd"

## echo "getToken: curl -m 20 -s $tokenURL -X POST -H \"Content-Type: application/x-www-form-urlencoded\" -d \"$clientString\""

response=$(curl -m 20 -s $tokenURL -X POST -H "Content-Type: application/x-www-form-urlencoded" -d "$clientString")
## echo "response: $response"
token=$(/usr/bin/osascript -l JavaScript << EoS
    ObjC.unwrap($response.access_token)
EoS
)

echo "**************************"
echo "*******************theToken: $token"
echo "**************************"

## get computer ID from Jamf server
#echo "get computer ID: curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H \"Accept: application/xml\" -H \"Authorization: Bearer $(echo $token | head -n15)...\""
compXml=$(/usr/bin/curl -m 20 -s ${server}JSSResource/computers/udid/$udid/subset/general -H "Accept: application/xml" -H "Authorization: Bearer $token")
echo "**************************"
echo "computer record: ${compXml}"
echo "**************************"
