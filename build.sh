#!/bin/sh

VER="alpha-test"
HOST="raw.githubusercontent.com"
AUTHOR="zZerooneXx"
PROJECT="Linux-server-build"
_SRC="https://$HOST/$AUTHOR/$PROJECT/main/src/"

RED=$(printf '\e[31m')
GREEN=$(printf '\e[32m')
YELLOW=$(printf '\e[33m')
PURPLE=$(printf '\e[35m')
PLAIN=$(printf '\e[0m')

_startsWith() {
  echo "$1" | grep "^$2" >/dev/null 2>&1
}

_isNumber() {
  [ "$1" -ne 0 ] >/dev/null 2>&1
}

_isIP() {
  echo "$1" | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >/dev/null 2>&1
}

_firstCharacter() {
  [ -n "$1" ] && echo "$1" | cut -c1
}

_success() {
  cat >&2 <<-EOF
	${PURPLE}[$(date)] ${GREEN}$1${PLAIN}
	EOF
}

_info() {
  cat >&2 <<-EOF
	${PURPLE}[$(date)] ${YELLOW}$1${PLAIN}
	EOF
}

_err() {
  cat >&2 <<-EOF
	${PURPLE}[$(date)] ${RED}$1${PLAIN}
	EOF
}

_err2() {
  cat >&2 <<-EOF
	${PURPLE}[$(date)] ${RED}$1 ${YELLOW}$2${PLAIN}
	EOF
}

_root() {
  user="$(id -un 2>/dev/null || true)"
  [ "$user" != "root" ] && _err "Permission error, please use root user to run this script" && exit 1
}

_exists() {
  if eval type type >/dev/null 2>&1; then
    eval type "$@" >/dev/null 2>&1
  elif command >/dev/null 2>&1; then
    command -v "$@" >/dev/null 2>&1
  else
    hash "$@" >/dev/null 2>&1
  fi
}

_host() {
  _exists ip && _INTERFACE_INFO="$(ip addr)"
  _SERVER_IP=$(echo "$_INTERFACE_INFO" |
    grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" |
    grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." |
    head -n 1)
  [ -z "$_SERVER_IP" ] && _SERVER_IP="$(curl -sSL -4 icanhazip.com)"
  echo "$_SERVER_IP"
}

_os() {
  [ -e /etc/centos-release ] && _DIST='centos' || [ -e /etc/redhat-release ] && _DIST='redhat'
  [ -e /etc/os-release ] && _DIST_VERSION=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')
  [ -z "$_DIST" ] || [ "$_DIST_VERSION" -lt "8" ] && _err "This script can not be run in your system now!" && exit 1
}

_arch() {
  _ARCH="$(uname -m)"
  [ "$_ARCH" != "x86_64" ] && _err "The current script only supports x86_64 systems. Your system is: $_ARCH" && exit 1
}

_iptRules() {
  _info "installing the iptables rules..."
  systemctl stop iptables
  systemctl stop ip6tables
  _IPTABLES=$(curl -sSL $_SRC/ipt/iptables)
  _IP6TABLES=$(curl -sSL $_SRC/ipt/ip6tables)
  [ -e /etc/ssh/sshd_config ] && _PORT=$(grep -oP '(?<=^Port\s)[0-9]+' /etc/ssh/sshd_config)
  [ "$_PORT" ] && _IPTABLES=$(echo "$_IPTABLES" | sed "s/--dports 22/--dports $_PORT/")
  cat >/etc/sysconfig/iptables <<-EOF
		$_IPTABLES
	EOF
  cat >/etc/sysconfig/ip6tables <<-EOF
		$_IP6TABLES
	EOF
  systemctl start iptables
  systemctl start ip6tables
  _success "iptables rules successfully installed!"
}

_preInstall() {
  ! _exists "dnf" && _err "DNF package manager must be installed!" && exit 1
  if _exists "firewalld" || ! _exists "iptables"; then
    printf "install iptables? [y/n]: "
    read -r yn
    if [ -n "$yn" ]; then
      case "$(_firstCharacter "$yn")" in
      y | Y)
        if _exists "firewalld"; then
          _info "uninstalling the firewalld..."
          systemctl stop firewalld
          systemctl disable firewalld >/dev/null 2>&1
          dnf -qy remove firewalld
          _success "firewalld successfully uninstalled!"
        fi
        if ! _exists "iptables"; then
          _info "installing the iptables..."
          dnf -qy install iptables-services
          systemctl enable iptables >/dev/null 2>&1
          systemctl enable ip6tables >/dev/null 2>&1
          _iptRules
          _success "iptables successfully installed!"
        fi
        ;;
      *)
        _err "for the script to work, you need to install iptables and new rules!"
        exit 1
        ;;
      esac
    else
      _err "for the script to work, you need to install iptables and new rules!"
      exit 1
    fi
  fi
  if ! _exists "bc"; then
    dnf -qy install bc >/dev/null 2>&1 || {
      _err "The operating system needs to be updated!" && exit 1
    }
  fi
}

_openPort() {
  grep -oqP "## $_NAME$" /etc/sysconfig/iptables && sed -i "/## $_NAME$/I,+2 d" /etc/sysconfig/iptables
  if [ -z "$2" ]; then
    sed -i "0,/^# INPUT PERMISSION FROM ALL HOSTS/!b;//a\## $_NAME\n-A INPUT -p tcp -m multiport --dports $1 -j ACCEPT\n" /etc/sysconfig/iptables
  else
    sed -i "0,/^# INPUT PERMISSION FROM ALL HOSTS/!b;//a\## $_NAME\n-A INPUT -p tcp -m multiport -s $2 --dports $1 -j ACCEPT\n" /etc/sysconfig/iptables
  fi
  systemctl restart iptables
}

_sys() {
  _info "installing the sysctl.conf..."
  if [ -e /proc/sys/net/ipv4/conf/all/rp_filter ]; then
    for filter in /proc/sys/net/ipv4/conf/*/rp_filter; do
      echo 1 >"$filter"
    done
  fi
  if [ -e /proc/sys/net/ipv4/conf/all/accept_source_route ]; then
    for route in /proc/sys/net/ipv4/conf/*/accept_source_route; do
      echo 0 >"$route"
    done
  fi
  _SYSCTL=$(curl -sSL $_SRC/sysctl.conf)
  [ -e /sys/class/net/"$_INTERFACE"/speed ] && _SPEED="$(cat /sys/class/net/"$_INTERFACE"/speed)"
  [ "$_SPEED" -eq "100" ] && _SYSCTL=$(echo "$_SYSCTL" | sed "s/16777216/2097152/g" | sed "s/1048576/65536/g" | sed "s/1GbE/100MbE/g")
  [ "$_SPEED" -eq "10000" ] && _SYSCTL=$(echo "$_SYSCTL" | sed "s/= 16777216/= 134217728/g" | sed "s/1048576 16777216/1048576 33554432/g" | sed "s/1GbE/10GbE/g")
  cat >/etc/sysctl.conf <<-EOF
		$(echo "$_SYSCTL" |
    sed "s/# MEM_BYTES \* 0.10 \/ 65536/$(echo "$_MEM_BYTES * 0.10 / 65536" | bc | cut -f 1 -d '.')/" |
    sed "s/# MEM_BYTES \/ 4194304 \* 256/$(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.')/" |
    sed "s/# MEM_BYTES \/ 1024 \* 0.01/$(echo "($_MEM_BYTES / 1024) * 0.01" | bc | cut -f 1 -d '.')/" |
    sed "s/# MEM_BYTES \* 0.90/$(echo "$_MEM_BYTES * 0.90" | bc | cut -f 1 -d '.')/" |
    sed "s/# MEM_BYTES \/ \$(getconf PAGE_SIZE)/$(echo "$_MEM_BYTES / $(getconf PAGE_SIZE)" | bc | cut -f 1 -d '.')/" |
    sed "s/# (MEM_BYTES \/ 4194304 \* 256) \* 2/$(($(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.') * 2))/")
	EOF
  /sbin/sysctl -e -p /etc/sysctl.conf >/dev/null 2>&1
  _success "sysctl.conf successfully installed!"
}

_ssh() {
  _info "installing the sshd_config..."
  if [ -z "$_PORT" ]; then
    [ -e /etc/ssh/sshd_config ] && _PORT=$(grep -oP '(?<=^Port\s)[0-9]+' /etc/ssh/sshd_config) || _PORT="22"
  fi
  _openPort "$_PORT" "$_IP"
  _SSHD=$(curl -sSL $_SRC/sshd_config)
  cat >/etc/ssh/sshd_config <<-EOF
		$(echo "$_SSHD" |
    sed "s/ListenAddress 0.0.0.0/ListenAddress $(_host)/" |
    sed "s/Port 22/Port $_PORT/")
	EOF
  systemctl restart sshd
  _success "sshd_config successfully installed!"
}

_psg() {
  if [ "$_CMD" = "psg-pkg" ]; then
    if ! _exists "psql"; then
      _info "installing the PostgreSQL..."
      dnf -qy module disable postgresql
      dnf -qy install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-$_DIST_VERSION-$_ARCH/pgdg-redhat-repo-latest.noarch.rpm"
      dnf -qy install postgresql13-server >/dev/null 2>&1
      /usr/pgsql-13/bin/postgresql-13-setup initdb >/dev/null 2>&1
      systemctl enable postgresql-13 >/dev/null 2>&1
      systemctl start postgresql-13
      if [ "$_DB" ] && [ "$_PASS" ]; then
        su postgres >/dev/null 2>&1 <<-EOF
					psql -c "CREATE DATABASE $_DB"
					psql -c "ALTER USER postgres WITH PASSWORD '$_PASS';"
					psql -c "GRANT ALL privileges ON DATABASE $_DB TO postgres;"
				EOF
      fi
      systemctl restart postgresql-13
      _success "PostgreSQL successfully installed!"
    else
      _info "PostgreSQL is already installed!"
    fi
  fi
  if [ "$_CMD" = "psg-cfg" ]; then
    if _exists "psql"; then
      if [ -z "$_PORT" ]; then
        [ -e /var/lib/pgsql/13/data/postgresql.conf ] && _PORT=$(grep -oP '(?<=^port)\W+[0-9]+' /var/lib/pgsql/13/data/postgresql.conf | tr -d " ='") || _PORT="5432"
      fi
      _openPort "$_PORT"
      if [ -z "$_CLIENTS" ] || [ "$_CLIENTS" -lt "20" ]; then
        [ -e /var/lib/pgsql/13/data/postgresql.conf ] && _CLIENTS=$(grep -oP '(?<=^max_connections)\W+[0-9]+' /var/lib/pgsql/13/data/postgresql.conf | tr -d " ='") || _CLIENTS="20"
      fi
      _AVG_NUMCORE=$(echo "$_NUMCORE / 2" | bc | cut -f 1 -d '.')
      [ "$_AVG_NUMCORE" -gt "4" ] && _AVG_NUMCORE="4"
      [ "$_AVG_NUMCORE" -lt "1" ] && _AVG_NUMCORE="1"
      _info "installing the pg_hba.conf and postgresql.conf..."
      _PG_HBA=$(curl -sSL $_SRC/postgresql/pg_hba.conf)
      [ "$_IP" ] && _PG_HBA=$(echo "$_PG_HBA" | sed "s~0.0.0.0/0~$_IP~")
      cat >/var/lib/pgsql/13/data/pg_hba.conf <<-EOF
				$_PG_HBA
			EOF
      _PSG=$(curl -sSL $_SRC/postgresql/postgresql.conf)
      cat >/var/lib/pgsql/13/data/postgresql.conf <<-EOF
				$(echo "$_PSG" |
        sed "s/'\*'/'$(_host)'/" |
        sed "s/port = 5432/port = $_PORT/" |
        sed "s~Europe\/London~$_TIMEZONE~" |
        sed "s/max_connections = 20/max_connections = $_CLIENTS/g" |
        sed "s/# MEM_MB \* 0.25/$(echo "$_MEM_MB * 0.25" | bc | cut -f 1 -d '.')MB/" |
        sed "s/# MEM_MB \* 0.75/$(echo "$_MEM_MB * 0.75" | bc | cut -f 1 -d '.')MB/" |
        sed "s/# MEM_MB \* 0.05/$(echo "$_MEM_MB * 0.05" | bc | cut -f 1 -d '.')MB/" |
        sed "s/# MEM_MB \/ CLIENTS \* 0.25/$(echo "$_MEM_MB / $_CLIENTS * 0.25" | bc | cut -f 1 -d '.')MB/" |
        sed "s/# MEM_MB \/ CLIENTS \* 0.4/$(echo "$_MEM_MB / $_CLIENTS * 0.4" | bc | cut -f 1 -d '.')MB/" |
        sed "s/# NUM CORES$/$_NUMCORE/g" |
        sed "s/# NUM CORES \/ 2/$(echo "$_AVG_NUMCORE" | bc | cut -f 1 -d '.')/g" |
        sed "s/# STACKSIZE(ulimit -s) \* 0.80/$(echo "$_STACKSIZE * 0.80" | bc | cut -f 1 -d '.')MB/")
			EOF
      systemctl restart postgresql-13
      _success "pg_hba.conf and postgresql.conf successfully installed!"
    else
      _info "PostgreSQL is not installed!"
    fi
  fi
}

_nginx() {
  if [ "$_CMD" = "nginx-pkg" ]; then
    if ! _exists "nginx"; then
      [ "$_DIST" = "redhat" ] && _DIST="rhel"
      _info "installing NGINX..."
      dnf -qy module disable php
      dnf -qy module disable nginx
      dnf -qy install "http://nginx.org/packages/$_DIST/$_DIST_VERSION/$_ARCH/RPMS/nginx-1.20.1-1.el8.ngx.$_ARCH.rpm"
      dnf -qy install nginx
      systemctl enable nginx >/dev/null 2>&1
      systemctl start nginx
      _success "NGINX successfully installed!"
    else
      _info "NGINX is already installed!"
    fi
  fi
  if [ "$_CMD" = "nginx-cfg" ]; then
    if _exists "nginx"; then
      [ -z "$_DOMAIN" ] && _err2 "Usage: $_COMMAND build.sh $_NAME" "-d domain.ltd" && exit 1
      _info 'installing the nginx.conf...'
      _NGINX=$(curl -sSL $_SRC/nginx/nginx.conf)
      rm -rf '/etc/nginx/conf.d'
      mkdir -p '/etc/nginx/conf.d/inc'
      [ "$_GZIP" ] && curl -sSL "$_SRC/nginx/gzip.conf" >/etc/nginx/conf.d/inc/gzip.conf
      [ "$_HEAD" ] && curl -sSL "$_SRC/nginx/header.conf" >/etc/nginx/conf.d/inc/header.conf
      if [ "$_SSL" ]; then
        curl -sSL "$_SRC/nginx/ssl.conf" >/etc/nginx/conf.d/srv.conf
      else
        curl -sSL "$_SRC/nginx/default.conf" >/etc/nginx/conf.d/srv.conf
      fi
      _SRVNAME=$(for d in $_DOMAIN; do
        printf "%s " "$d" "*.$d"
      done)
      for d in $_DOMAIN; do
        mkdir -p "/var/www/$d"
      done
      sed -i "s/domain.tld \*\.domain.tld/$(echo "$_SRVNAME" | sed 's/.$//')/" '/etc/nginx/conf.d/srv.conf'
      [ "$_WWW" ] && sed -i '/www\./I,+2 d' '/etc/nginx/conf.d/srv.conf'
      [ -e /etc/resolv.conf ] && _RESOLV="$(cat /etc/resolv.conf)"
      _RESOLVIP=$(echo "$_RESOLV" | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}")
      [ "$_RESOLVIP" ] && _NGINX=$(echo "$_NGINX" | sed "s/resolver [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/resolver $_RESOLVIP/")
      cat >/etc/nginx/nginx.conf <<-EOF
				$(echo "$_NGINX" | sed "s/# worker_connections \* NUM CORES \* 2/$(echo "$_NUMCORE * 1024 * 2" | bc | cut -f 1 -d '.')/")
			EOF
      systemctl restart nginx
      _success 'nginx.conf successfully installed!'
    else
      _info 'NGINX is not installed!'
    fi
  fi
}

_ipv6() {
  _info 'Removing the IPv6 interface...'
  if [ -e /proc/sys/net/ipv6/conf/all/disable_ipv6 ]; then
    for ipv6 in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
      echo 1 >"$ipv6"
    done
  fi
  _GRUBFILE=/etc/default/grub
  grep -Eq 'ipv6.disable' $_GRUBFILE || sed -i 's/^GRUB_CMDLINE_LINUX="/&ipv6.disable=1 /' $_GRUBFILE
  grep -Eq 'ipv6.disable=0' $_GRUBFILE | sed -i 's/ipv6.disable=0/ipv6.disable=1/' $_GRUBFILE
  grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
  sed -i '/IPV6/d' "/etc/sysconfig/network-scripts/ifcfg-$_INTERFACE"
  sed -i '/ip6/d' '/etc/hosts'
  _success 'IPv6 interface successfully Removed!'
}

_showHelp() {
  cat >&2 <<-EOF
	${YELLOW}Usage: build.sh <command> <name> [parameters ...]
	Commands:
  -h, --help                 Show this help message.
  -v, --version              Show version info.
  --pkg                      Install Packages from Repositories.
  --cfg                      Install Сonfiguration Settings.
  --disable                  Turn off options.
	Parameters:
  -d <domain.tld>            Specifies a domain in NGINX.
	Optional parameters:
  -port [0-9]                Specifies the server listening port.
  -clients [0-9]             Specifies a limit of connected clients to the server.
  -db <name>                 Specifies a database name.
  -pass <password>           Specifies a password.
  --ssl                      Using ssl.
  --www                      Using www in NGINX.
  --gzip                     Using gzip in NGINX.
  --head                     Using head in NGINX.
  ${PLAIN}
	EOF
}

_version() {
  cat >&2 <<-EOF
	$PROJECT
	version: $VER
	EOF
}

_process() {
  _COMMAND=""
  _CMD=""
  _NAME=""
  _DB=""
  _PASS=""
  _WWW=""
  _GZIP=""
  _HEAD=""
  _SSL=""
  _DOMAIN=""
  _TIMEZONE=$(timedatectl | awk '/Time zone:/ {print $3}')
  _NUMCORE=$(grep -c 'processor' /proc/cpuinfo)
  _MEM_BYTES=$(awk '/MemTotal:/ { printf "%0.f", $2 * 1024 }' /proc/meminfo)
  _MEM_MB=$(awk '/MemTotal:/ { printf "%0.f", $2 / 1024 }' /proc/meminfo)
  _STACKSIZE=$(sh -c "ulimit -s" | awk '{ print $1 / 1024 }')
  _INTERFACE="$(ip -o route get 32/32 | awk '{print $5}')"

  while [ $# -gt 0 ]; do
    _COMMAND="$1"
    case "$1" in
    --help | -h)
      _showHelp
      exit
      ;;
    --version | -v)
      _version
      exit
      ;;
    --pkg)
      _NAME="$2"
      case "$_NAME" in
      NGINX) _CMD="nginx-pkg" ;;
      PSG) _CMD="psg-pkg" ;;
      *) [ -z "$_NAME" ] && _err2 "Usage: build.sh" "$_COMMAND ... [parameters ...]" && exit 1 || _err2 "Unknown component:" "$_NAME" && exit 1 ;;
      esac
      shift
      ;;
    --cfg)
      _NAME="$2"
      case "$_NAME" in
      NGINX) _CMD="nginx-cfg" ;;
      PSG) _CMD="psg-cfg" ;;
      SYS) _CMD="sys" ;;
      SSH) _CMD="ssh" ;;
      IPT) _CMD="ipt" ;;
      *) [ -z "$_NAME" ] && _err2 "Usage: build.sh" "$_COMMAND ... [parameters ...]" && exit 1 || _err2 "Unknown component:" "$_NAME" && exit 1 ;;
      esac
      shift
      ;;
    --disable)
      _NAME="$2"
      case "$_NAME" in
      IPv6) _CMD="ipv6" ;;
      *) [ -z "$_NAME" ] && _err2 "Usage: build.sh" "$_COMMAND ... [parameters ...]" && exit 1 || _err2 "Unknown component:" "$_NAME" && exit 1 ;;
      esac
      shift
      ;;
    -port)
      if [ "$2" ]; then
        if ! _isNumber "$2"; then
          _err2 "'$2' invalid for parameter" "$1" && exit 1
        fi
        if [ -z "$_PORT" ]; then
          _PORT="$2"
        else
          _PORT="$_PORT,$2"
        fi
      fi
      shift
      ;;
    -ip)
      if [ "$2" ]; then
        if _startsWith "$2" "-" || ! _isIP "$2"; then
          _err2 "'$2' invalid for parameter" "$1" && exit 1
        fi
        if [ -z "$_IP" ]; then
          _IP="$2"
        else
          _IP="$_IP,$2"
        fi
      fi
      shift
      ;;
    -clients)
      if [ "$2" ]; then
        if ! _isNumber "$2"; then
          _err2 "'$2' invalid for parameter" "$1" && exit 1
        fi
        if [ -z "$_CLIENTS" ]; then
          _CLIENTS="$2"
        fi
      fi
      shift
      ;;
    -db)
      _DB="$2"
      shift
      ;;
    -pass)
      _PASS="$2"
      shift
      ;;
    --ssl)
      _SSL="on"
      ;;
    --www)
      _WWW="on"
      ;;
    --gzip)
      _GZIP="on"
      ;;
    --head)
      _HEAD="on"
      ;;
    --dev)
      _SRC="https://$HOST/$AUTHOR/$PROJECT/dev/src/"
      ;;
    -d)
      if [ "$2" ]; then
        if _startsWith "$2" "-"; then
          _err2 "'$2' invalid for parameter" "$1" && exit 1
        fi
        if [ -z "$_DOMAIN" ]; then
          _DOMAIN="$2"
        else
          _DOMAIN="$_DOMAIN $2"
        fi
      fi
      shift
      ;;
    *)
      _err2 "Invalid command:" "$1" && exit 1
      ;;
    esac
    shift 1
  done

  _preInstall

  case "$_CMD" in
  nginx-pkg) _nginx ;;
  psg-pkg) _psg "$_DB" "$_PASS" ;;
  nginx-cfg) _nginx "$_DOMAIN" ;;
  psg-cfg) _psg "$_PORT" "$_CLIENTS" "$_IP" ;;
  ssh) _ssh "$_PORT" ;;
  sys) _sys ;;
  ipv6) _ipv6 ;;
  ipt) _iptRules ;;
  esac
}

main() {
  _root
  _os
  _arch
  [ -z "$1" ] && _showHelp && exit 1
  if _startsWith "$1" '-'; then _process "$@"; else
    _err2 "Invalid command:" "$*" && _showHelp && exit 1
  fi
}

main "$@"
