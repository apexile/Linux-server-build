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
        --nginx)
        NGINX=true
        shift
        ;;
        --ssh)
        SSH=true
        shift
        ;;
        --ipt)
        IPT=true
        shift
        ;;
        --restart)
        RESTART=true
        shift
        ;;
        --sshport=*)
        SSHPORT="${arg#*=}"
        shift
        ;;
        --pass)
        PASSWORD="$2"
        shift
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

if [ "$PASSWORD" ]
then
    echo "$PASSWORD" | passwd "root" --stdin
fi

#########################################################################################
###################################### SYSCTL.CONF ######################################
#########################################################################################

SYSCTL=$(echo "$(curl -s -L $SOURCE/sysctl.conf)" | sed "s/#max_orphan/$MAX_ORPHAN/g" | sed "s/#file_max/$FILE_MAX/g" | sed "s/#min_free/$MIN_FREE/g" | sed "s/#shmmax/$SHMMAX/g" | sed "s/#shmall/$SHMALL/g" | sed "s/#max_tw/$MAX_TW/g")
>/etc/sysctl.conf cat << EOF 
$SYSCTL
EOF
/sbin/sysctl -p /etc/sysctl.conf

#########################################################################################
###################################### NGINX.CONF #######################################
#########################################################################################

if [ "$NGINX" ]; then
NGINX=$(echo "$(curl -s -L $SOURCE/nginx.conf)" | sed "s/example.com/$DOMAIN/g")
>/etc/nginx/nginx.conf cat << EOF 
$NGINX
EOF
fi

#########################################################################################
###################################### SSHD_CONFIG ######################################
#########################################################################################

if [ "$SSH" ]; then
SSH=$(echo "$(curl -s -L $SOURCE/sshd_config)" | sed "s/#change-port/$SSHPORT/g")
>/etc/ssh/sshd_config cat << EOF 
$SSH
EOF
systemctl restart sshd
fi

#########################################################################################
###################################### IPTABLES.SH ######################################
#########################################################################################

if [ "$IPT" ]; then
    curl -s https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src/iptables.sh | sh -s -- --ssh=$SSHPORT
fi

if [ "$RESTART" ]
then
    shutdown -r now
fi

exit $?