#!/bin/sh

VER=alpha
HOST="raw.githubusercontent.com"
AUTHOR="zZerooneXx"
PROJECT_NAME="Linux-server-build"
_SRC="https://$HOST/$AUTHOR/$PROJECT_NAME/main/src/"

RED=$(printf '\e[31m')
GREEN=$(printf '\e[32m')
YELLOW=$(printf '\e[33m')
PURPLE=$(printf '\e[35m')
PLAIN=$(printf '\e[0m')

_startswith() {
  echo "$1" | grep "^$2" >/dev/null 2>&1
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
  local user=""
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

_is_number() {
  expr "$1" + 1 >/dev/null 2>&1
}

_host() {
  local server_ip=""
  local interface_info=""

  if _exists ip; then
    interface_info="$(ip addr)"
  elif _exists ifconfig; then
    interface_info="$(ifconfig)"
  fi

  server_ip=$(echo "$interface_info" |
    grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" |
    grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." |
    head -n 1)

  if [ -z "$server_ip" ]; then
    server_ip="$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com)"
  fi

  echo "$server_ip"
}

_os() {
  [ -r /etc/os-release ] && lsb_dist="$(. /etc/os-release && echo "$ID")"
  [ -r /etc/os-release ] && dist_version="$(. /etc/os-release && echo "$VERSION_ID")"

  if [ "$lsb_dist" = "centos" ] || [ "$lsb_dist" = "redhat" ]; then
    if [ "$dist_version" != "8" ]; then
      _err "This script can not be run in your system now!"
      exit 1
    fi
  else
    _err "This script can not be run in your system now!"
    exit 1
  fi
}

_arch() {
  arch="$(uname -m)"
  if [ "$arch" = "amd64" ] || [ "$arch" = "x86_64" ]; then
    arch='x86_64'
  else
    _err "The current script only supports x86_64 systems. Your system is: $arch"
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
    for i in ${1//,/ }; do
      firewall-cmd --zone=public --permanent --add-port="$i"/tcp >/dev/null 2>&1
    done
    systemctl restart firewalld
  elif _exists "iptables"; then
    iptables -A INPUT -p tcp -m multiport --dports "$1" -j ACCEPT
    systemctl restart iptables
  fi
}

_psg_eof() {
  local _PSG=$(curl -s -L $_SRC/postgresql.conf)
  cat >/var/lib/pgsql/13/data/postgresql.conf <<-EOF
		$(echo "$_PSG" |
    sed "s/'\*'/'$(_host)'/g" |
    sed "s/port = 5432/port = $_port/g" |
    sed "s~#timezone~$_TIMEZONE~g" |
    sed "s/max_connections = 20/max_connections = $_clients/g" |
    sed "s/#shared_buffers/$(echo "$_MEM_MB * 0.25" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#effective_cache_size/$(echo "$_MEM_MB * 0.75" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#maintenance_work_mem/$(echo "$_MEM_MB * 0.05" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#work_mem/$(echo "($_MEM_MB / $_clients) * 0.25" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#temp_buffers/$(echo "($_MEM_MB / $_clients) * 0.4" | bc | cut -f 1 -d '.')MB/g" |
    sed "s/#numcore/$(echo "$_NUMCORE")/g" |
    sed "s/#avgnumcore/$(echo "$_AVG_NUMCORE" | bc | cut -f 1 -d '.')/g" |
    sed "s/#max_stack_depth/$(echo "$_STACKSIZE * 0.80" | bc | cut -f 1 -d '.')MB/g")
	EOF
}

_pg_hba_eof() {
  local _PG_HBA=$(curl -s -L $_SRC/pg_hba.conf)
  cat >/var/lib/pgsql/13/data/pg_hba.conf <<-EOF
		$(echo "$_PG_HBA")
	EOF
}

_pgdb_eof() {
  su postgres <<-EOF
		psql -c "CREATE DATABASE $_db"
		psql -c "ALTER USER postgres WITH PASSWORD '$_pass';"
		psql -c "GRANT ALL privileges ON DATABASE $_db TO postgres;"
	EOF
}

_sys_eof() {
  local _SYSCTL=$(curl -s -L $_SRC/sysctl.conf)
  ip a | grep -Eq "inet6" || _SYSCTL=$(echo "$_SYSCTL" | sed '/net.ipv6/d')
  cat >/etc/sysctl.conf <<-EOF
		$(echo "$_SYSCTL" |
    sed "s/#max_orphan/$(echo "$_MEM_BYTES * 0.10 / 65536" | bc | cut -f 1 -d '.')/g" |
    sed "s/#file_max/$(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.')/g" |
    sed "s/#min_free/$(echo "($_MEM_BYTES / 1024) * 0.01" | bc | cut -f 1 -d '.')/g" |
    sed "s/#shmmax/$(echo "$_MEM_BYTES * 0.90" | bc | cut -f 1 -d '.')/g" |
    sed "s/#shmall/$(expr $_MEM_BYTES / $(getconf PAGE_SIZE))/g" |
    sed "s/#max_tw/$(($(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.') * 2))/g")
	EOF
}

_ssh_eof() {
  local _SSHD=$(curl -s -L $_SRC/sshd_config)
  cat >/etc/ssh/sshd_config <<-EOF
		$(echo "$_SSHD" |
    sed "s/ListenAddress 0.0.0.0/ListenAddress $(_host)/g" |
    sed "s/Port 22/Port $_port/g")
	EOF
}

_nginx_eof() {
  echo $_SRC
  local _NGINX=$(curl -s -L $_SRC/nginx.conf)
  if [ "$_domain" ]; then
    _srvname=$(for d in $_domain; do
      printf "$d *.$d "
    done)
    for d in $_domain; do
      mkdir -p /var/www/$d
    done
    _NGINX=$(echo "$_NGINX" | sed "s/domain.tld \*\.domain.tld/$(echo "$_srvname" | sed 's/.$//')/g")
  fi

  if [ "$_http" = "80,443" ]; then
    _NGINX=$(echo "$_NGINX" | sed '/# DEFAULT/,/# SSL/d')
  else
    _NGINX=$(echo "$_NGINX" | sed '/# SSL/,/# END/d')
  fi

  if [ "$_www" ]; then
    _NGINX=$(echo "$_NGINX" | sed '/www\./I,+2 d')
  fi

  ip a | grep -Eq "inet " || _NGINX=$(echo "$_NGINX" | sed '/listen [0-9]/d')
  ip a | grep -Eq "inet6" || _NGINX=$(echo "$_NGINX" | sed '/listen \[::]/d')

  cat >/etc/nginx/nginx.conf <<-EOF
		$(echo "$_NGINX")
	EOF
}

_sys() {
  _info "installing the sysctl.conf..."
  _sys_eof
  /sbin/sysctl -e -p /etc/sysctl.conf >/dev/null 2>&1
  _success "sysctl.conf successfully installed!"
}

_ssh() {
  _SSHDFILE="/etc/ssh/sshd_config"
  if [ "$_port" ]; then
    _port="$_port"
  else
    if [ -f "$_SSHDFILE" ]; then
      grep -oqP '(?<=Port )[0-9]+' $_SSHDFILE && _port=$(grep -oP '(?<=Port )[0-9]+' $_SSHDFILE) || _port="22"
    else
      _port="22"
    fi
  fi
  _openPort "$_port"
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
      dnf -qy install https://download.postgresql.org/pub/repos/yum/reporpms/EL-$dist_version-$arch/pgdg-redhat-repo-latest.noarch.rpm
      dnf -qy install postgresql13-server >/dev/null 2>&1
      /usr/pgsql-13/bin/postgresql-13-setup initdb >/dev/null 2>&1
      systemctl enable postgresql-13 >/dev/null 2>&1
      systemctl start postgresql-13
      if [ "$_db" ] && [ "$_pass" ]; then
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
      if [ "$_port" ]; then
        _port="$_port"
      else
        if [ -f "$_PSGFILE" ]; then
          grep -oqP '(?<=port = )[0-9]+' $_PSGFILE && _port=$(grep -oP '(?<=port = )[0-9]+' $_PSGFILE) || _port="5432"
        fi
        _port="5432"
      fi
      if [ "$_clients" ]; then
        _clients="$_clients"
        if [ $_clients -lt "20" ]; then
          _clients="20"
        fi
      else
        if [ -f "$_PSGFILE" ]; then
          grep -oqP '(?<=max_connections = )[0-9]+' $_PSGFILE && _clients=$(grep -oP '(?<=max_connections = )[0-9]+' $_PSGFILE) || _clients="20"
        else
          _clients="20"
        fi
      fi
      _openPort "$_port"

      _AVG_NUMCORE=$(echo "$_NUMCORE / 2" | bc | cut -f 1 -d '.')
      if [ $_AVG_NUMCORE -gt "4" ]; then
        _AVG_NUMCORE="4"
      fi
      if [ $_AVG_NUMCORE -lt "1" ]; then
        _AVG_NUMCORE="1"
      fi
      _info "installing the pg_hba.conf..."
      _pg_hba_eof
      _success "pg_hba.conf successfully installed!"
      _info "installing the postgresql.conf..."
      _psg_eof
      systemctl restart postgresql-13
      _success "postgresql.conf successfully installed!"
    else
      _info "PostgreSQL is not installed!"
    fi
  fi
}

_nginx() {
  if [ "$lsb_dist" = "redhat" ]; then
    local lsb_dist="rhel"
  fi
  if [ "$_CMD" = "nginx-pkg" ]; then
    if ! _exists "nginx"; then
      _info "installing NGINX..."
      dnf -qy module disable php
      dnf -qy module disable nginx
      dnf -qy install http://nginx.org/packages/$lsb_dist/$dist_version/$arch/RPMS/nginx-1.20.1-1.el8.ngx.$arch.rpm
      dnf -qy install nginx
      systemctl enable nginx >/dev/null 2>&1
      systemctl start nginx
      _openPort $_http
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

_ipt() {
  _info "installing the iptables rules..."
  systemctl stop iptables
  curl -s $_SRC/iptables.sh | sh
  systemctl start iptables
  _success "iptables rules successfully installed!"
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

  exit $1
}

_process() {
  _CMD=""
  _db=""
  _pass=""
  _www=""
  _http="80"
  _TIMEZONE=$(timedatectl | awk '/Time zone:/ {print $3}')
  _NUMCORE=$(cat /proc/cpuinfo | grep processor | wc -l)
  _MEM_BYTES=$(awk '/MemTotal:/ { printf "%0.f", $2 * 1024 }' /proc/meminfo)
  _MEM_MB=$(awk '/MemTotal:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo)
  _STACKSIZE=$(ulimit -s | awk '{ print $1 / 1024 }')

  while [ $# -gt 0 ]; do
    case "$1" in
    --help | -h)
      showhelp
      return
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
        if [ -z "$_port" ]; then
          _port="$2"
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
        if [ -z "$_clients" ]; then
          _clients="$2"
        fi
      fi
      shift
      ;;
    -db)
      _db="$2"
      shift
      ;;
    -pass)
      _pass="$2"
      shift
      ;;
    --ssl)
      _http="80,443"
      ;;
    --www)
      _www="on"
      ;;
    --dev)
      _SRC="https://$HOST/$AUTHOR/$PROJECT_NAME/dev/src/"
      ;;
    -d)
      if [ "$2" ]; then
        if _startswith "$2" "-"; then
          _err_arg "'$2' invalid for parameter" "$1"
          exit 1
        fi
        if [ -z "$_domain" ]; then
          _domain="$2"
        else
          _domain="$_domain $2"
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
  psg-pkg) _psg "$_db" "$_pass" ;;
  nginx-cfg) _nginx "$_domain" ;;
  psg-cfg) _psg "$_port" "$_clients" ;;
  ssh) _ssh "$_port" ;;
  sys) _sys ;;
  ipv6) _ipv6 ;;
  ipt) _ipt ;;
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
