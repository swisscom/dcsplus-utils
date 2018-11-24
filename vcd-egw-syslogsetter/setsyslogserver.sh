#!/bin/bash
#
# Simple script used to set a syslog server for a particular Edge Gateway
# This script is necessary since the Syslog settings cannot be adjusted in the
# vCloudDirector Web UI
#
# Unfortunately, the applied configuration cannot be verified, since the
# effective syslog server settings cannot be retrieved after setting them.
#

VCD_HOST='vcd-pod-alpha.swisscomcloud.com'
VCD_API_USER='api_vcd_tbd@PRO-00tbd'
VCD_API_PASS='...'
VCD_ORG_NAME='PRO-00tbd'
VCD_VDC_NAME='MyDynamicDataCenter'
VCD_EGW_NAME='PRO-005013856_MyEdgeGateway'
SYSLOG_SERVER_IP='192.168.100.10'

# Cookies need to be used, in case of a WAF doing session management in front
# of the vCloudDirector cells
COOKIEFILE=$(mktemp)
HEADERFILE=$(mktemp)

curl -s -o /dev/null -b $COOKIEFILE https://$VCD_HOST/api/versions

# Logging in
curl -s -o /dev/null -H 'Accept: application/*;version=27.0' -b $COOKIEFILE -c $COOKIEFILE -X POST -D $HEADERFILE -u $VCD_API_USER:$VCD_API_PASS https://$VCD_HOST/api/sessions
AUTHH=$(cat $HEADERFILE | grep 'x-vcloud-authorization')
AUTHH="${AUTHH%%[[:cntrl:]]}"

ORG_URL=$(curl -s -H 'Accept: application/*;version=27.0' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X GET https://$VCD_HOST/api/org/ | grep "\"$VCD_ORG_NAME\"" | cut -d '"' -f 2 )
VDC_URL=$(curl -s -H 'Accept: application/*;version=27.0' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X GET $ORG_URL | grep "application/vnd.vmware.vcloud.vdc+xml" | grep "\"$VCD_VDC_NAME\"" | cut -d '"' -f 4 )
EGW_URL=$(curl -s -H 'Accept: application/*;version=27.0' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X GET $VDC_URL | grep "<Link rel=\"edgeGateways\"" | cut -d '"' -f 4 )
EGW_URL=$(curl -s -H 'Accept: application/*;version=27.0' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X GET $EGW_URL | grep "EdgeGatewayRecord" | cut -d '"' -f 18 )
CONFIG_URL=$(curl -s -H 'Accept: application/*;version=27.0' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X GET $EGW_URL | grep "<Link rel=\"edgeGateway:configureSyslogServerSettings\"" | cut -d '"' -f 4 )
XML="<?xml version=\"1.0\" encoding=\"UTF-8\"?><SyslogServerSettings xmlns=\"http://www.vmware.com/vcloud/v1.5\"><TenantSyslogServerSettings><SyslogServerIp>$SYSLOG_SERVER_IP</SyslogServerIp></TenantSyslogServerSettings></SyslogServerSettings>"
curl -v -H 'Accept: application/*;version=27.0' -H 'Content-Type: application/vnd.vmware.vcloud.SyslogSettings+xml' -H "$AUTHH" -b $COOKIEFILE -c $COOKIEFILE -X POST -d "$XML" $CONFIG_URL

rm $COOKIEFILE
rm $HEADERFILE
