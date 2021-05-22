#!/bin/bash
#
# Author: https://github.com/zZerooneXx

which bc
if [ $? -ne 0 ]; then
    echo "You need to install bc"
fi

copy_sysctl=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sysctl.conf)

mem_bytes=$(awk '/MemTotal:/ { printf "%0.f",$2 * 1024}' /proc/meminfo)
shmmax=$(echo "$mem_bytes * 0.90" | bc | cut -f 1 -d '.')
shmall=$(expr $mem_bytes / $(getconf PAGE_SIZE))
max_orphan=$(echo "$mem_bytes * 0.10 / 65536" | bc | cut -f 1 -d '.')
file_max=$(echo "$mem_bytes / 4194304 * 256" | bc | cut -f 1 -d '.')
max_tw=$(($file_max*2))
min_free=$(echo "($mem_bytes / 1024) * 0.01" | bc | cut -f 1 -d '.')

result_sysctl=$(echo "$copy_sysctl" | sed "s/#shmmax/$shmmax/g" | sed "s/#shmall/$shmall/g" | sed "s/#max_orphan=/$max_orphan=/g" | sed "s/#file_max/$file_max/g" | sed "s/#max_tw/$max_tw/g" | sed "s/#min_free/$min_free/g")

#sysctl=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sysctl.conf)
#sshd_config=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sshd_config)
#iptables=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/IPT.sh)
#nginx=$(curl -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/nginx.conf)

#>/etc/sysctl.conf cat << EOF 
>/var/test/testo.conf cat << EOF 

$result_sysctl

EOF
# /sbin/sysctl -p /etc/sysctl.conf
exit $?