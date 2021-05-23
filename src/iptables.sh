#!/bin/bash
#############################################################
# Name:    FireWall script                                  #
# Usage:   setup iptables firewall rules for domian/ip      #
# Website: https://apexile.com                              #
# Author:  ZerooneX <zZerooneXx@gmail.com>                  #
# Github:  https://github.com/zZerooneXx                    #
#############################################################

#########################################################################################
################################### REMOVE FIREWALLD ####################################
#########################################################################################

which firewalld
if [ $? -ne 1 ]; then
    systemctl disable firewalld
    systemctl stop firewalld
    dnf remove firewalld -y
fi

#########################################################################################
################################### INSTALL IPTABLES ####################################
#########################################################################################

which iptables
if [ $? -ne 0 ]; then
    dnf install iptables-services -y
    systemctl enable iptables
fi

#########################################################################################
######################################### PORTS #########################################
#########################################################################################

SSH=22
HTTP=80,443,444,8080,8443
POSTGRESQL=5432
IDENT=113
RAGEMP=22005,22006

#########################################################################################
######################################### ARGS ##########################################
#########################################################################################

for arg in "$@"
do
    case $arg in
        -s=*|--ssh=*)
        SSH="${arg#*=}"
        shift
        ;;
    esac
done

#########################################################################################
##################################### ANTI SPOOFING #####################################
#########################################################################################

if [ -e /proc/sys/net/ipv4/conf/all/rp_filter ]
then
    for filter in /proc/sys/net/ipv4/conf/*/rp_filter
    do
        echo 1 > $filter
    done
fi

#########################################################################################
#################################### DEFAULT POLICY #####################################
#########################################################################################

# clear all rules
iptables -F
iptables -X
iptables -Z
# do not use forwarding / NAT
iptables -t nat -F
iptables -t nat -X
iptables -t nat -Z
# do not alter packets
iptables -t mangle -F
iptables -t mangle -X
iptables -t mangle -Z
# set default policy
iptables -P INPUT   ACCEPT
iptables -P OUTPUT  ACCEPT
iptables -P FORWARD ACCEPT
iptables -P INPUT   DROP
iptables -P FORWARD DROP
# accept traffic from loopback interface (localhost).
iptables -A INPUT -i lo -j ACCEPT
# allow established TCP connections:
iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -j ACCEPT

#########################################################################################
############################### Anti-Attack: Stealth Scan ###############################
#########################################################################################

iptables -N STEALTH_SCAN # make a chain with the name "STEALTH_SCAN"
iptables -A STEALTH_SCAN -j LOG --log-prefix "stealth_scan_attack: "
iptables -A STEALTH_SCAN -j DROP

# stealth scan-like packets jump to the "STEALTH_SCAN" chain
iptables -A INPUT -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL NONE                             -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN                      -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST                      -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ALL SYN,RST,ACK,FIN,URG              -j STEALTH_SCAN

iptables -A INPUT -p tcp --tcp-flags FIN,RST FIN,RST                      -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,FIN FIN                          -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,PSH PSH                          -j STEALTH_SCAN
iptables -A INPUT -p tcp --tcp-flags ACK,URG URG                          -j STEALTH_SCAN

#########################################################################################
############# Anti-Attack: Port scanning with fragment packets, DOS attacks #############
#########################################################################################

iptables -A INPUT -f -j LOG --log-prefix 'fragment_packet:'
iptables -A INPUT -f -j DROP

#########################################################################################
############################## Anti-Attack: Ping of Death ###############################
#########################################################################################

iptables -N PING_OF_DEATH # make a chain with the name "PING_OF_DEATH"
iptables -A PING_OF_DEATH -p icmp --icmp-type echo-request \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 10 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_PING_OF_DEATH \
         -j RETURN

# discard ICMP that exceeds the limit
iptables -A PING_OF_DEATH -j LOG --log-prefix "ping_of_death_attack: "
iptables -A PING_OF_DEATH -j DROP

# ICMP jumps to "PING_OF_DEATH" chain
iptables -A INPUT -p icmp --icmp-type echo-request -j PING_OF_DEATH

#########################################################################################
############################# Anti-Attack: SYN Flood Attack #############################
#########################################################################################

iptables -N SYN_FLOOD # make a chain with the name "SYN_FLOOD"
iptables -A SYN_FLOOD -p tcp --syn \
         -m hashlimit \
         --hashlimit 200/s \
         --hashlimit-burst 3 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_SYN_FLOOD \
         -j RETURN

# discard SYN packets that exceed the limit
iptables -A SYN_FLOOD -j LOG --log-prefix "syn_flood_attack: "
iptables -A SYN_FLOOD -j DROP

# SYN packets jump to the "SYN_FLOOD" chain
iptables -A INPUT -p tcp --syn -j SYN_FLOOD

#########################################################################################
########################### Anti-Attack: HTTP DoS/DDoS Attack ###########################
#########################################################################################

iptables -N HTTP_DOS # make a chain with the name "HTTP_DOS"
iptables -A HTTP_DOS -p tcp -m multiport --dports $HTTP \
         -m hashlimit \
         --hashlimit 1/s \
         --hashlimit-burst 100 \
         --hashlimit-htable-expire 300000 \
         --hashlimit-mode srcip \
         --hashlimit-name t_HTTP_DOS \
         -j RETURN

# discard connections that exceed the limit
iptables -A HTTP_DOS -j LOG --log-prefix "http_dos_attack: "
iptables -A HTTP_DOS -j DROP

# packets to HTTP jump to the "HTTP_DOS" chain
iptables -A INPUT -p tcp -m multiport --dports $HTTP -j HTTP_DOS

#########################################################################################
############################# Anti-Attack: IDENT port probe #############################
#########################################################################################

iptables -A INPUT -p tcp -m multiport --dports $IDENT -j REJECT --reject-with tcp-reset

#########################################################################################
############################# Anti-Attack: SSH Brute Force ##############################
#########################################################################################

iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --set
iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 180 --hitcount 8 -j LOG --log-prefix "ssh_brute_force: "
iptables -A INPUT -p tcp --syn -m multiport --dports $SSH -m recent --name ssh_attack --rcheck --seconds 180 --hitcount 8 -j REJECT --reject-with tcp-reset

#########################################################################################
## Packets destined for all hosts (broadcast address, multicast address) are discarded ##
#########################################################################################

iptables -A INPUT -d 192.168.1.255     -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 192.168.1.255     -j DROP
iptables -A INPUT -d 255.255.255.255   -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 255.255.255.255   -j DROP
iptables -A INPUT -d 224.0.0.1         -j LOG --log-prefix "drop_broadcast: "
iptables -A INPUT -d 224.0.0.1         -j DROP

#########################################################################################
############################ Input permission from all hosts ############################
#########################################################################################

# ICMP
iptables -A INPUT -p icmp -j ACCEPT

# HTTP, HTTPS
iptables -A INPUT -p tcp -m multiport --dports $HTTP -j ACCEPT

# SSH
iptables -A INPUT -p tcp -m multiport --dports $SSH -j ACCEPT

# POSTGRESQL
iptables -A INPUT -p tcp -m multiport --dports $POSTGRESQL -j ACCEPT

# RAGEMP
iptables -A INPUT -p tcp -m multiport --dports $RAGEMP -j ACCEPT
iptables -A INPUT -p udp -m multiport --dports $RAGEMP -j ACCEPT

#########################################################################################
############ Log and discard anything that does not apply to the above rules ############
#########################################################################################

iptables -A INPUT -j LOG --log-prefix "drop: "
iptables -A INPUT -j DROP

/sbin/iptables-save  > /etc/sysconfig/iptables

systemctl start iptables
systemctl restart iptables

exit $?