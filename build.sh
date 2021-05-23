#!/bin/bash
#########################################################################################
#################        Name:    Linux server build script             #################
#################        Website: https://apexile.com                   #################
#################        Author:  ZerooneX <zZerooneXx@gmail.com>       #################
#################        Github:  https://github.com/zZerooneXx         #################
#########################################################################################

#########################################################################################
###################################### INSTALL BC #######################################
#########################################################################################

which bc
if [ $? -ne 0 ]; then
    dnf install bc -y
fi

#########################################################################################
####################################### VARIABLES #######################################
#########################################################################################

SOURCE="https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src"
NGINX=0
SSH=0
IPT=0
SSHPORT=22
DOMAIN="example.com"
HOST=$(hostname -I | awk '{ print $1 }')
TAGS=()

MEM_BYTES=$(awk '/MemTotal:/ { printf "%0.f",$2 * 1024}' /proc/meminfo)
MAX_ORPHAN=$(echo "$MEM_BYTES * 0.10 / 65536" | bc | cut -f 1 -d '.')
FILE_MAX=$(echo "$MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.')
MIN_FREE=$(echo "($MEM_BYTES / 1024) * 0.01" | bc | cut -f 1 -d '.')
SHMMAX=$(echo "$MEM_BYTES * 0.90" | bc | cut -f 1 -d '.')
SHMALL=$(expr $MEM_BYTES / $(getconf PAGE_SIZE))
MAX_TW=$(($FILE_MAX*2))

#########################################################################################
####################################### ARGUMENTS #######################################
#########################################################################################

for arg in "$@"
do
    case $arg in
        -n|--nginx)
        NGINX=1
        shift
        ;;
        -s|--ssh)
        SSH=1
        shift
        ;;
        -i|--ipt)
        IPT=1
        shift
        ;;
        -sp=*|--sshport=*)
        SSHP="${arg#*=}"
        shift
        ;;
        -d|--domain)
        DOMAIN="$2"
        shift
        shift
        ;;
        *)
        TAGS+=("$1")
        shift
        ;;
    esac
done

#########################################################################################
###################################### SYSCTL.CONF ######################################
#########################################################################################

SYSCTL=$(echo "$(curl -s -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sysctl.conf)" | sed "s/#max_orphan/$MAX_ORPHAN/g" | sed "s/#file_max/$FILE_MAX/g" | sed "s/#min_free/$MIN_FREE/g" | sed "s/#shmmax/$SHMMAX/g" | sed "s/#shmall/$SHMALL/g" | sed "s/#max_tw/$MAX_TW/g")
>/etc/sysctl.conf cat << EOF 
$SYSCTL
EOF
/sbin/sysctl -p /etc/sysctl.conf

#########################################################################################
###################################### NGINX.CONF #######################################
#########################################################################################

if [ $NGINX != 0 ]; then
NGINX=$(echo "$(curl -s -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/nginx.conf)" | sed "s/example.com/$DOMAIN/g")
>/etc/nginx/nginx.conf cat << EOF 
$NGINX
EOF
fi

#########################################################################################
###################################### SSHD_CONFIG ######################################
#########################################################################################

if [ $SSH != 0 ]; then
SSH=$(echo "$(curl -s -L https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/sshd_config)" | sed "s/#change-port/$SSHPORT/g")
>/etc/ssh/sshd_config cat << EOF 
$SSH
EOF
fi

#########################################################################################
###################################### IPTABLES.SH ######################################
#########################################################################################

if [ $IPT != 0 ]; then
    curl -s https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/iptables.sh | sh -s=$SSHPORT
fi





echo "# Other arguments: ${TAGS[*]}"
echo "### FINAL ###"

exit $?