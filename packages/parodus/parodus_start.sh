#!/bin/sh
##########################################################################
# If not stated otherwise in this file or this component's Licenses.txt
# file the following copyright and licenses apply:
#
# Copyright 2018 RDK Management
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
##########################################################################

DeviceNetworkInterface=`grep ETHERNET_INTERFACE /etc/device.properties | cut -d'=' -f2`

# Checking the file exists
if [ -e /sys/class/net/$DeviceNetworkInterface/address ]; then
    HW_MAC=$(cat /sys/class/net/$DeviceNetworkInterface/address)
elif [ -e /sys/class/net/eth0/address ]; then
    HW_MAC=$(cat /sys/class/net/eth0/address)
    DeviceNetworkInterface="eth0"
fi

ModelName=$(rbuscli get Device.DeviceInfo.ModelName | awk '/Value/ {print $NF}' | tr -d '\r\n')
SerialNumber=$(rbuscli get Device.DeviceInfo.SerialNumber | awk '/Value/ {print $NF}' | tr -d '\r\n')
Manufacturer=$(rbuscli get Device.DeviceInfo.Manufacturer | awk '/Value/ {print $NF}' | tr -d '\r\n')
LastRebootReason=$(rbuscli get Device.DeviceInfo.X_RDKCENTRAL-COM_LastRebootReason | awk '/Value/ {print $NF}' | tr -d '\r\n')
FirmwareName=$(rbuscli get Device.DeviceInfo.X_CISCO_COM_FirmwareName | awk '/Value/ {print $NF}' | tr -d '\r\n')
BootTime=$(rbuscli get Device.DeviceInfo.X_RDKCENTRAL-COM_BootTime | awk '/Value/ {print $NF}' | tr -d '\r\n')
MaxPingWaitTimeInSec=180;
ServerURL=`grep SERVERURL /etc/device.properties | cut -d'=' -f2`
BackOffMax=9;
PARODUS_URL=tcp://127.0.0.1:6666;
SSL_CERT_PATH=/etc/ssl/certs/ca-certificates.crt

echo "Framing command for parodus"

command="/usr/bin/parodus \
--hw-model=$ModelName \
--hw-serial-number=$SerialNumber \
--hw-manufacturer=$Manufacturer \
--hw-last-reboot-reason=$LastRebootReason \
--fw-name=$FirmwareName \
--boot-time=$BootTime \
--hw-mac=$HW_MAC \
--webpa-ping-time=180 \
--webpa-interface-used=$DeviceNetworkInterface \
--webpa-url=$ServerURL \
--webpa-backoff-max=$BackOffMax  \
--parodus-local-url=$PARODUS_URL \
--partner-id=comcast \
--ssl-cert-path=$SSL_CERT_PATH \
--force-ipv4"

echo $command >/tmp/parodusCmd.cmd

echo "Starting parodus with the following arguments"
cat /tmp/parodusCmd.cmd

$command &
