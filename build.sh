#!/bin/bash
#
# Author: https://github.com/zZerooneXx

which bc
if [ $? -ne 0 ]; then
    echo "You need to install bc"
fi

mem_bytes=$(awk '/MemTotal:/ { printf "%0.f",$2 * 1024}' /proc/meminfo)
shmmax=$(echo "$mem_bytes * 0.90" | bc | cut -f 1 -d '.')
shmall=$(expr $mem_bytes / $(getconf PAGE_SIZE))
max_orphan=$(echo "$mem_bytes * 0.10 / 65536" | bc | cut -f 1 -d '.')
file_max=$(echo "$mem_bytes / 4194304 * 256" | bc | cut -f 1 -d '.')
max_tw=$(($file_max*2))
min_free=$(echo "($mem_bytes / 1024) * 0.01" | bc | cut -f 1 -d '.')

#sysctl=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sysctl.sh)
#sshd_config=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sshd_config)
#iptables=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/IPT.sh)
#nginx=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/nginx.conf)

test=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sshd_config)

#>/etc/sysctl.conf cat << EOF 
>/var/test/testo.conf cat << EOF 

$test

EOF

# /sbin/sysctl -p /etc/sysctl.conf
exit $?