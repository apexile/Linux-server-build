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

_startswith() {
  echo "$1" | grep "^$2" >/dev/null 2>&1
}

_is_number() {
  [ "$1" -ne 0 ] >/dev/null 2>&1
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

_err_arg() {
  cat >&2 <<-EOF
	${PURPLE}[$(date)] ${RED}$1 ${YELLOW}${2}${PLAIN}
	EOF
}

_root() {
  user="$(id -un 2>/dev/null || true)"
  if [ "$user" != "root" ]; then
    _err "Permission error, please use root user to run this script"
    exit 1
  fi
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
  if _exists ip; then
    _INTERFACE_INFO="$(ip addr)"
  elif _exists ifconfig; then
    _INTERFACE_INFO="$(ifconfig)"
  fi

  _SERVER_IP=$(echo "$_INTERFACE_INFO" |
    grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" |
    grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." |
    head -n 1)

  if [ -z "$_SERVER_IP" ]; then
    _SERVER_IP="$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com)"
  fi

  echo "$_SERVER_IP"
}

_os() {
  [ -r /etc/os-release ] && _ID=$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"') && _VERSION=$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')

  if [ "$_ID" = "redhat" ] || [ "$_ID" = "centos" ]; then
    if [ "$_VERSION" != "8" ]; then
      _err "This script can not be run in your system now!"
      exit 1
    fi
  else
    _err "This script can not be run in your system now!"
    exit 1
  fi
}

_arch() {
  _ARCH="$(uname -m)"
  if [ "$_ARCH" = "amd64" ] || [ "$_ARCH" = "x86_64" ]; then
    _ARCH='x86_64'
  else
    _err "The current script only supports x86_64 systems. Your system is: $_ARCH"
    exit 1
  fi
}

_preinstall() {
  if ! _exists "dnf"; then
    _err "DNF package manager must be installed!"
    exit 1
  fi

  if ! _exists "bc"; then
    dnf -qy install bc >/dev/null 2>&1 || {
      _err "The operating system needs to be updated!"
      exit 1
    }
  fi
}

_openPort() {
  if _exists "firewalld"; then
    for i in $(echo "$1" | tr ',' '\n'); do
      firewall-cmd --zone=public --permanent --add-port="$i"/tcp >/dev/null 2>&1
    done
    systemctl restart firewalld
  elif _exists "iptables"; then
    iptables -A INPUT -p tcp -m multiport --dports "$1" -j ACCEPT
    systemctl restart iptables
  fi
}

_psg_eof() {
  _PSG=$(curl -s -L $_SRC/postgresql.conf)
  cat >/var/lib/pgsql/13/data/postgresql.conf <<-EOF
		$(echo "$_PSG" |
    sed "s/'\*'/'$(_host)'/g" |
    sed "s/port = 5432/port = $_PORT/g" |
    sed "s~#timezone~$_TIMEZONE~g" |
    sed "s/max_connections = 20/max_connections = $_CLIENTS/g" |
    sed "s/#shared_buffers/$(echo "$_MEM_MB * 0.25" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#effective_cache_size/$(echo "$_MEM_MB * 0.75" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#maintenance_work_mem/$(echo "$_MEM_MB * 0.05" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#work_mem/$(echo "($_MEM_MB / $_CLIENTS) * 0.25" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#temp_buffers/$(echo "($_MEM_MB / $_CLIENTS) * 0.4" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#numcore/$_NUMCORE/g" |
    sed "s/#avgnumcore/$(echo "$_AVG_NUMCORE" | bc | cut -f 1 -d '.')/g" |
    sed "s/#max_stack_depth/$(echo "$_STACKSIZE * 0.80" | bc | cut -f 1 -d '.')MB/g")
	EOF
}

_pg_hba_eof() {
  _PG_HBA=$(curl -s -L $_SRC/pg_hba.conf)
  cat >/var/lib/pgsql/13/data/pg_hba.conf <<-EOF
		$_PG_HBA
	EOF
}

_pgdb_eof() {
  su postgres <<-EOF
		psql -c "CREATE DATABASE $_DB"
		psql -c "ALTER USER postgres WITH PASSWORD '$_PASS';"
		psql -c "GRANT ALL privileges ON DATABASE $_DB TO postgres;"
	EOF
}

_sys_eof() {
  _SYSCTL=$(curl -s -L $_SRC/sysctl.conf)
  ip a | grep -Eq "inet6" || _SYSCTL=$(echo "$_SYSCTL" | sed '/net.ipv6/d')
  cat >/etc/sysctl.conf <<-EOF
		$(echo "$_SYSCTL" |
    sed "s/#max_orphan/$(echo "$_MEM_BYTES * 0.10 / 65536" | bc | cut -f 1 -d '.')/g" |
    sed "s/#file_max/$(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.')/g" |
    sed "s/#min_free/$(echo "($_MEM_BYTES / 1024) * 0.01" | bc | cut -f 1 -d '.')/g" |
    sed "s/#shmmax/$(echo "$_MEM_BYTES * 0.90" | bc | cut -f 1 -d '.')/g" |
    sed "s/#shmall/$(echo "$_MEM_BYTES / $(getconf PAGE_SIZE)" | bc | cut -f 1 -d '.')/g" |
    sed "s/#max_tw/$(($(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.') * 2))/g")
	EOF
}

_ssh_eof() {
  _SSHD=$(curl -s -L $_SRC/sshd_config)
  cat >/etc/ssh/sshd_config <<-EOF
		$(echo "$_SSHD" |
    sed "s/ListenAddress 0.0.0.0/ListenAddress $(_host)/g" |
    sed "s/Port 22/Port $_PORT/g")
	EOF
}

_nginx_eof() {
  _NGINX=$(curl -s -L $_SRC/nginx.conf)
  if [ "$_DOMAIN" ]; then
    _SRVNAME=$(for d in $_DOMAIN; do
      printf "%s " "$d" "*.$d"
    done)
    for d in $_DOMAIN; do
      mkdir -p "/var/www/$d"
    done
    _NGINX=$(echo "$_NGINX" | sed "s/domain.tld \*\.domain.tld/$(echo "$_SRVNAME" | sed 's/.$//')/g")
  fi

  if [ "$_HTTP" = "80,443" ]; then
    _NGINX=$(echo "$_NGINX" | sed '/# DEFAULT/,/# SSL/d')
  else
    _NGINX=$(echo "$_NGINX" | sed '/# SSL/,/# END/d')
  fi

  if [ "$_WWW" ]; then
    _NGINX=$(echo "$_NGINX" | sed '/www\./I,+2 d')
  fi

  ip a | grep -Eq "inet\s" || _NGINX=$(echo "$_NGINX" | sed '/listen [0-9]/d')
  ip a | grep -Eq "inet6" || _NGINX=$(echo "$_NGINX" | sed '/listen \[::]/d')

  cat >/etc/nginx/nginx.conf <<-EOF
		$_NGINX
	EOF
}

_sys() {
  _info "installing the sysctl.conf..."
  _sys_eof
  /sbin/sysctl -e -p /etc/sysctl.conf >/dev/null 2>&1
  _success "sysctl.conf successfully installed!"
}

_ssh() {
  if [ -z "$_PORT" ]; then
    [ -r /etc/ssh/sshd_config ] && _PORT=$(grep -oP '(?<=^Port\s)[0-9]+' /etc/ssh/sshd_config) || _PORT="22"
  fi
  _openPort "$_PORT"
  _info "installing the sshd_config..."
  _ssh_eof
  systemctl restart sshd
  _success "sshd_config successfully installed!"
}

_psg() {
  if [ "$_CMD" = "psg-pkg" ]; then
    if ! _exists "psql"; then
      _info "installing the PostgreSQL..."
      dnf -qy module disable postgresql
      dnf -qy install "https://download.postgresql.org/pub/repos/yum/reporpms/EL-$_VERSION-$_ARCH/pgdg-redhat-repo-latest.noarch.rpm"
      dnf -qy install postgresql13-server >/dev/null 2>&1
      /usr/pgsql-13/bin/postgresql-13-setup initdb >/dev/null 2>&1
      systemctl enable postgresql-13 >/dev/null 2>&1
      systemctl start postgresql-13
      if [ "$_DB" ] && [ "$_PASS" ]; then
        _pgdb_eof >/dev/null 2>&1
      fi
      systemctl restart postgresql-13
      _success "PostgreSQL successfully installed!"
    else
      _info "PostgreSQL is already installed!"
    fi
  fi

  if [ "$_CMD" = "psg-cfg" ]; then
    if _exists "psql"; then
      _PSGFILE="/var/lib/pgsql/13/data/postgresql.conf"
      if [ -z "$_PORT" ]; then
        [ -r /var/lib/pgsql/13/data/postgresql.conf ] && _PORT=$(grep -oP '(?<=^port)\W+[0-9]+' /var/lib/pgsql/13/data/postgresql.conf | tr -d " ='") || _PORT="5432"
      fi
      if [ -z "$_CLIENTS" ]; then
        [ -r /var/lib/pgsql/13/data/postgresql.conf ] && _CLIENTS=$(grep -oP '(?<=^max_connections)\W+[0-9]+' /var/lib/pgsql/13/data/postgresql.conf | tr -d " ='") || _CLIENTS="20"
      fi
      if [ "$_CLIENTS" -lt "20" ]; then
        _CLIENTS="20"
      fi
      _openPort "$_PORT"

      _AVG_NUMCORE=$(echo "$_NUMCORE / 2" | bc | cut -f 1 -d '.')
      if [ "$_AVG_NUMCORE" -gt "4" ]; then
        _AVG_NUMCORE="4"
      fi
      if [ "$_AVG_NUMCORE" -lt "1" ]; then
        _AVG_NUMCORE="1"
      fi
      _info "installing the pg_hba.conf and postgresql.conf..."
      _pg_hba_eof
      _psg_eof
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
      if [ "$_ID" = "redhat" ]; then
        _ID="rhel"
      fi
      _info "installing NGINX..."
      dnf -qy module disable php
      dnf -qy module disable nginx
      dnf -qy install "http://nginx.org/packages/$_ID/$_VERSION/$_ARCH/RPMS/nginx-1.20.1-1.el8.ngx.$_ARCH.rpm"
      dnf -qy install nginx
      systemctl enable nginx >/dev/null 2>&1
      systemctl start nginx
      _openPort "$_HTTP"
      _success "NGINX successfully installed!"
    else
      _info "NGINX is already installed!"
    fi
  fi

  if [ "$_CMD" = "nginx-cfg" ]; then
    if _exists "nginx"; then
      _info "installing the nginx.conf..."
      _nginx_eof
      systemctl restart nginx
      _success "nginx.conf successfully installed!"
    else
      _info "NGINX is not installed!"
    fi
  fi
}

_ipv6() {
  _info "Removing the IPv6 interface..."
  _GRUBFILE=/etc/default/grub
  grep -Eq "ipv6.disable" $_GRUBFILE || sed -i 's/^GRUB_CMDLINE_LINUX="/&ipv6.disable=1 /' $_GRUBFILE
  grep -Eq "ipv6.disable=0" $_GRUBFILE | sed -i 's/ipv6.disable=0/ipv6.disable=1/' $_GRUBFILE
  grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
  _success "IPv6 interface successfully Removed!"
}

showhelp() {
  cat >&2 <<-EOF
	${YELLOW}Usage: build.sh <command> ... [parameters ...]
	Commands:
  -h, --help                 Show this help message.
  -v, --version              Show version info.
  --pkg                      Install Packages from Repositories.
  --cfg                      Install Сonfiguration Settings.
  --disable                  Turn off options.
	Parameters:
  -port [0-9]                Specifies the server listening port.
  -clients [0-9]             Specifies a limit of connected clients to the server.
  -db <name>                 Specifies a database name.
  -pass <password>           Specifies a password.
  -d <domain.tld>            Specifies a domain.
  --ssl                      Using ssl.
  --www                      Using www.
  ${PLAIN}
	EOF
}

version() {
  echo "$PROJECT"
  echo "version: $VER"
}

_process() {
  _CMD=""
  _DB=""
  _PASS=""
  _WWW=""
  _HTTP="80"
  _DOMAIN=""
  _TIMEZONE=$(timedatectl | awk '/Time zone:/ {print $3}')
  _NUMCORE=$(grep -c 'processor' /proc/cpuinfo)
  _MEM_BYTES=$(awk '/MemTotal:/ { printf "%0.f", $2 * 1024 }' /proc/meminfo)
  _MEM_MB=$(awk '/MemTotal:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo)
  _STACKSIZE=$(sh -c "ulimit -s" | awk '{ print $1 / 1024 }')

  while [ $# -gt 0 ]; do
    case "$1" in
    --help | -h)
      showhelp
      exit
      ;;
    --version | -v)
      version
      exit
      ;;
    --pkg)
      case "$2" in
      NGINX) _CMD="nginx-pkg" ;;
      PSG) _CMD="psg-pkg" ;;
      *)
        [ -z "$2" ] && _err_arg "Usage: build.sh " "$1 ... [parameters ...]" && exit 1
        if [ "$2" ]; then
          _err_arg "Invalid command:" "$2"
        fi
        exit 1
        ;;
      esac
      shift
      ;;
    --cfg)
      case "$2" in
      NGINX) _CMD="nginx-cfg" ;;
      PSG) _CMD="psg-cfg" ;;
      SYS) _CMD="sys" ;;
      SSH) _CMD="ssh" ;;
      IPT) _CMD="ipt" ;;
      *)
        [ -z "$2" ] && _err_arg "Usage: build.sh " "$1 ... [parameters ...]" && exit 1
        if [ "$2" ]; then
          _err_arg "Invalid command:" "$2"
        fi
        exit 1
        ;;
      esac
      shift
      ;;
    --disable)
      case "$2" in
      IPv6) _CMD="ipv6" ;;
      *)
        [ -z "$2" ] && _err_arg "Usage: build.sh " "$1 ... [parameters ...]" && exit 1
        if [ "$2" ]; then
          _err_arg "Invalid command:" "$2"
        fi
        exit 1
        ;;
      esac
      shift
      ;;
    -port)
      if [ "$2" ]; then
        if ! _is_number "$2"; then
          _err_arg "'$2' invalid for parameter" "$1"
          exit 1
        fi
        if [ -z "$_PORT" ]; then
          _PORT="$2"
        fi
      fi
      shift
      ;;
    -clients)
      if [ "$2" ]; then
        if ! _is_number "$2"; then
          _err_arg "'$2' invalid for parameter" "$1"
          exit 1
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
      _HTTP="80,443"
      ;;
    --www)
      _WWW="on"
      ;;
    --dev)
      _SRC="https://$HOST/$AUTHOR/$PROJECT/dev/src/"
      ;;
    -d)
      if [ "$2" ]; then
        if _startswith "$2" "-"; then
          _err_arg "'$2' invalid for parameter" "$1"
          exit 1
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
      _err_arg "Invalid command:" "$1"
      exit 1
      ;;
    esac
    shift 1
  done

  case "$_CMD" in
  nginx-pkg) _nginx ;;
  psg-pkg) _psg "$_DB" "$_PASS" ;;
  nginx-cfg) _nginx "$_DOMAIN" ;;
  psg-cfg) _psg "$_PORT" "$_CLIENTS" ;;
  ssh) _ssh "$_PORT" ;;
  sys) _sys ;;
  ipv6) _ipv6 ;;
  ipt) curl -sSL $_SRC/iptables.sh | sh ;;
  *)
    if [ "$_CMD" ]; then
      _err_arg "Invalid command:" "$_CMD"
    fi
    exit 1
    ;;
  esac
}

main() {
  _root
  _os
  _arch
  _preinstall
  [ -z "$1" ] && showhelp && exit 1
  if _startswith "$1" '-'; then _process "$@"; else
    _err_arg "Invalid command:" "$*"
    showhelp
  fi
}

main "$@"
