#!/bin/sh

###########################
echo "Setup docker with external iptables"
inFile=$(cat /etc/docker/daemon.json | grep -c "iptables")
if [ $inFile -eq 0 ];
  then
    mkdir -p /etc/docker
    cat << EOF >> /etc/docker/daemon.json
{
  "iptables" : false
}
EOF
    echo "restart docker" && systemctl restart docker
else
   echo "iptables not managed in docker"
fi

############################
echo "Disable OS firewalls like UFW and FirewallD"
systemctl stop ufw
systemctl disable ufw

systemctl stop firewalld
systemctl disable firewalld

##########################
ipt=$(which iptables)
#interface=$(ip route | grep default | sed -e "s/^.*dev.//" -e "s/.proto.*//")

# flush all rules
$ipt -F
$ipt -X
$ipt -Z
$ipt -t filter --flush
$ipt -t nat    --flush
$ipt -t mangle --flush

# Secure ssh access
$ipt -A INPUT -p tcp --dport 22 -m state --state NEW -s 0.0.0.0/0 -j ACCEPT

### BLOCK INPUT (test) - so docker ports are blocked
$ipt -P INPUT DROP
$ipt -P OUTPUT ACCEPT

# Enable free use of loopback interfaces
$ipt -A INPUT -i lo -j ACCEPT
$ipt -A OUTPUT -o lo -j ACCEPT

# Accept inbound TCP packets
$ipt -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# === anti scan ===
$ipt -N SCANS
$ipt -A SCANS -p tcp --tcp-flags FIN,URG,PSH FIN,URG,PSH -j DROP
$ipt -A SCANS -p tcp --tcp-flags ALL ALL -j DROP
$ipt -A SCANS -p tcp --tcp-flags ALL NONE -j DROP
$ipt -A SCANS -p tcp --tcp-flags SYN,RST SYN,RST -j DROP
####################

#    #No spoofing
#    if [ -e /proc/sys/net/ipv4/conf/all/ip_filter ]; then
#        for filtre in /proc/sys/net/ipv4/conf/*/rp_filter
#        do
#            echo > 1 $filtre
#        done
#    fi
#    echo "[Anti-spoofing is ready]"
#
#    #No synflood
#    if [ -e /proc/sys/net/ipv4/tcp_syncookies ]; then
#        echo 1 > /proc/sys/net/ipv4/tcp_syncookies
#    fi
#    echo "[Anti-synflood is ready]"
    
#Make sure NEW incoming tcp connections are SYN packets
$ipt -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
# Packets with incoming fragments
$ipt -A INPUT -f -j DROP
# incoming malformed XMAS packets
$ipt -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
# Incoming malformed NULL packets
$ipt -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

#Drop broadcast
$ipt -A INPUT -m pkttype --pkt-type broadcast -j DROP

# Docker interface 
$ipt -A FORWARD -o docker0 -j DOCKER
$ipt -A FORWARD -i docker0 ! -o docker0 -j ACCEPT
$ipt -A FORWARD -i docker0 -o docker0 -j ACCEPT
# Allow Docker tracffic
#$ipt -A FORWARD -o docker0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Accept inbound ICMP messages
$ipt -A INPUT -p ICMP --icmp-type 8 -s 0.0.0.0/0 -j ACCEPT
$ipt -A INPUT -p ICMP --icmp-type 11 -s 0.0.0.0/0 -j ACCEPT

########################
echo "Setup iptables" from docker ports

## Test docker ports (allow)
#$ipt -A INPUT -p tcp --dport 9000 -m state --state NEW -s 0.0.0.0/0 -j ACCEPT
ports=$(ss -plnt | grep docker | awk '{ print $4 }' |  cut -d: -f2)

for s in $ports
do
	$ipt -A INPUT -p tcp --dport ${s} -m state --state NEW -s 0.0.0.0/0 -j ACCEPT
done	


iptables-save
