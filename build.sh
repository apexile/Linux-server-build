#!/bin/bash

#########################################################################################
#################        Name:    LINUX SERVER BUILD SCRIPT             #################
#################        Website: https://apexile.com                   #################
#################        Author:  ZerooneX <zZerooneXx@gmail.com>       #################
#################        GitHub:  https://github.com/zZerooneXx         #################
#########################################################################################

_SRC="https://raw.githubusercontent.com/zZerooneXx/Linux-server-build/main/src"

which bc &>/dev/null
if [ $? -ne 0 ]; then
	dnf -qy install bc
fi

_startswith() {
	_str="$1"
	_sub="$2"
	echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}

_endswith() {
	_str="$1"
	_sub="$2"
	echo "$_str" | grep -- "$_sub\$" >/dev/null 2>&1
}

_contains() {
	_str="$1"
	_sub="$2"
	echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}

__red() {
	printf '\33[1;31m%b\33[0m' "$1"
}

__green() {
	printf '\33[1;32m%b\33[0m' "$1"
}

__yellow() {
	printf '\33[1;33m%b\33[0m' "$1"
}

__purple() {
	printf '\33[1;35m%b\33[0m' "$1"
}

__cyan() {
	printf '\33[1;36m%b\33[0m' "$1"
}

_proc() {
	__purple "[$(date)] " >&1
	__cyan "$@" >&1
	printf "\n" >&1
}

_success() {
	__purple "[$(date)] " >&1
	__green "$@" >&1
	printf "\n" >&1
}

_warn() {
	__purple "[$(date)] " >&1
	__yellow "$@" >&1
	printf "\n" >&1
}

_err() {
	__purple "[$(date)] " >&2
	if [ -z "$2" ]; then
		__red "$1" >&2
	else
		__red "$1='$2'" >&2
	fi
	printf "\n" >&2
	return 1
}

_checkSudo() {
	if [ "$SUDO_GID" ] && [ "$SUDO_COMMAND" ] && [ "$SUDO_USER" ] && [ "$SUDO_UID" ]; then
		if [ "$SUDO_USER" = "root" ] && [ "$SUDO_UID" = "0" ]; then
			return 0
		fi
		if [ -n "$SUDO_COMMAND" ]; then
			_endswith "$SUDO_COMMAND" /bin/su || _contains "$SUDO_COMMAND" "/bin/su " || grep "^$SUDO_COMMAND\$" /etc/shells >/dev/null 2>&1
			return $?
		fi
		return 1
	fi
	return 0
}

_openPort() {
	which firewalld &>/dev/null
	if [ $? -ne 1 ]; then
		for i in ${1//,/ }; do
			firewall-cmd --zone=public --permanent --add-port=${i}/tcp &>/dev/null
		done
		systemctl restart firewalld
	else
		which iptables &>/dev/null
		if [ $? -ne 1 ]; then
			iptables -A INPUT -p tcp -m multiport --dports $1 -j ACCEPT
			systemctl restart iptables
		fi
	fi
}

_exists() {
	cmd="$1"
	if [ -z "$cmd" ]; then
		_warn "Usage: _exists cmd"
		return 1
	fi

	if eval type type >/dev/null 2>&1; then
		eval type "$cmd" >/dev/null 2>&1
	elif command >/dev/null 2>&1; then
		command -v "$cmd" >/dev/null 2>&1
	else
		hash "$cmd" >/dev/null 2>&1
	fi
	ret="$?"
	return $ret
}

_psg_eof() {
	cat >/var/lib/pgsql/13/data/postgresql.conf <<EOF
$(echo "$(curl -s -L $_SRC/postgresql.conf)" |
		sed "s/'\*'/'$_HOST'/g" |
		sed "s/port = 5432/port = $_PGPORT/g" |
		sed "s~#timezone~$_TIMEZONE~g" |
		sed "s/max_connections = 20/max_connections = $_PGCONN/g" |
		sed "s/#shared_buffers/$(echo "$_MEM_MB * 0.25" | bc | cut -f 1 -d '.')MB/g" |
		sed "s/#effective_cache_size/$(echo "$_MEM_MB * 0.75" | bc | cut -f 1 -d '.')MB/g" |
		sed "s/#maintenance_work_mem/$(echo "$_MEM_MB * 0.05" | bc | cut -f 1 -d '.')MB/g" |
		sed "s/#work_mem/$(echo "($_MEM_MB / $_PGCONN) * 0.25" | bc | cut -f 1 -d '.')MB/g" |
		sed "s/#temp_buffers/$(echo "($_MEM_MB / $_PGCONN) * 0.4" | bc | cut -f 1 -d '.')MB/g" |
		sed "s/#numcore/$(echo "$_NUMCORE")/g" |
		sed "s/#avgnumcore/$(echo "$_AVG_NUMCORE" | bc | cut -f 1 -d '.')/g" |
		sed "s/#max_stack_depth/$(echo "$_STACKSIZE * 0.80" | bc | cut -f 1 -d '.')MB/g")
EOF
}

_pg_hba_eof() {
	cat >/var/lib/pgsql/13/data/pg_hba.conf <<EOF
$(echo "$(curl -s -L $_SRC/pg_hba.conf)")
EOF
}

_pgdb_eof() {
	su postgres <<EOF
psql -c "CREATE DATABASE $_PGDB"
psql -c "ALTER USER postgres WITH PASSWORD '$_PGPASS';"
psql -c "GRANT ALL privileges ON DATABASE $_PGDB TO postgres;"
EOF
}

_sys_eof() {
	cat >/etc/sysctl.conf <<EOF
$(echo "$(curl -s -L $_SRC/sysctl.conf)" |
		sed "s/#max_orphan/$(echo "$_MEM_BYTES * 0.10 / 65536" | bc | cut -f 1 -d '.')/g" |
		sed "s/#file_max/$(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.')/g" |
		sed "s/#min_free/$(echo "($_MEM_BYTES / 1024) * 0.01" | bc | cut -f 1 -d '.')/g" |
		sed "s/#shmmax/$(echo "$_MEM_BYTES * 0.90" | bc | cut -f 1 -d '.')/g" |
		sed "s/#shmall/$(expr $_MEM_BYTES / $(getconf PAGE_SIZE))/g" |
		sed "s/#max_tw/$(($(echo "$_MEM_BYTES / 4194304 * 256" | bc | cut -f 1 -d '.') * 2))/g")
EOF
}

_ssh_eof() {
	cat >/etc/ssh/sshd_config <<EOF
$(echo "$(curl -s -L $_SRC/sshd_config)" |
		sed "s/ListenAddress 0.0.0.0/ListenAddress $_HOST/g" |
		sed "s/Port 22/Port $_SSHPORT/g")
EOF
}

_nginx_eof() {
	cat >/etc/nginx/nginx.conf <<EOF
$(echo "$(curl -s -L $_SRC/nginx.conf)" |
		sed "s/domain.tld/$_DOMAIN/g")
EOF
}

_sys() {
	if [ "${_CMD}" = "cfg" ]; then
		_proc "installing the sysctl.conf..."
		_sys_eof
		/sbin/sysctl -e -p /etc/sysctl.conf >/dev/null 2>&1
		_success "sysctl.conf successfully installed!"
	else
		_err "sys unknown..."
	fi
}

_ssh() {
	if [ "${_CMD}" != "cfg" ]; then
		_err "Unknown : ssh"
	else
		_SSHDFILE="/etc/ssh/sshd_config"
		if [ -f "$_SSHDFILE" ]; then
			_SSHPORT=$(echo "$(grep -oP '(?<=Port )[0-9]+' $_SSHDFILE)")
		fi
		if [ -z "${arg[0]//[0-9]/}" ] && [ -n "${arg[0]}" ]; then
			_SSHPORT="${arg[0]}"
			_openPort "$_SSHPORT"
		fi
		if [ -z "$_SSHPORT" ]; then
			_SSHPORT="22"
		fi
		_proc "installing the sshd_config..."
		_ssh_eof
		systemctl restart sshd
		_success "sshd_config successfully installed!"
	fi
}

_psg() {
	if [ "${_CMD}" = "pkg" ]; then
		which psql &>/dev/null
		if [ $? -ne 0 ]; then
			_proc "installing the PostgreSQL..."
			dnf -qy module disable postgresql
			dnf -qy install https://download.postgresql.org/pub/repos/yum/reporpms/EL-8-x86_64/pgdg-redhat-repo-latest.noarch.rpm
			dnf -qy install postgresql13-server &>/dev/null
			/usr/pgsql-13/bin/postgresql-13-setup initdb &>/dev/null
			systemctl enable postgresql-13 &>/dev/null
			systemctl start postgresql-13
			if [ "${arg[0]}" ] && [ "${arg[1]}" ]; then
				_PGDB="${arg[0]}"
				_PGPASS="${arg[1]}"
				echo "$_PGPASS" | passwd "postgres" --stdin &>/dev/null
				_pgdb_eof &>/dev/null
			fi
			systemctl restart postgresql-13
			_success "PostgreSQL successfully installed!"
		else
			_warn "PostgreSQL is already installed!"
		fi
	fi

	if [ "${_CMD}" = "cfg" ]; then
		which psql &>/dev/null
		if [ $? -ne 1 ]; then
			_PSGFILE="/var/lib/pgsql/13/data/postgresql.conf"
			if [ -f "$_PSGFILE" ]; then
				_PGPORT=$(echo "$(grep -oP '(?<=port = )[0-9]+' $_PSGFILE)")
				_PGCONN=$(echo "$(grep -oP '(?<=max_connections = )[0-9]+' $_PSGFILE)")
			fi
			if [ -z "${arg[0]//[0-9]/}" ] && [ -n "${arg[0]}" ]; then
				_PGPORT="${arg[0]}"
				_openPort "$_PGPORT"
			fi
			if [ -z "${arg[1]//[0-9]/}" ] && [ -n "${arg[1]}" ]; then
				_PGCONN="${arg[1]}"
			fi
			if [ -z "$_PGPORT" ]; then
				_PGPORT="5432"
				_openPort "$_PGPORT"
			fi
			if [ -z "$_PGCONN" ] || (($_PGCONN < "20")); then
				_PGCONN="20"
			fi
			if (($_AVG_NUMCORE > "4")); then
				_AVG_NUMCORE="4"
			else
				if (($_AVG_NUMCORE < "1")); then
					_AVG_NUMCORE="1"
				fi
			fi
			_proc "installing the pg_hba.conf..."
			_pg_hba_eof
			_success "pg_hba.conf successfully installed!"
			_proc "installing the postgresql.conf..."
			_psg_eof
			systemctl restart postgresql-13
			_success "postgresql.conf successfully installed!"
		else
			_warn "PostgreSQL is not installed!"
		fi
	fi
}

_nginx() {
	if [ "${_CMD}" = "pkg" ]; then
		which nginx &>/dev/null
		if [ $? -ne 0 ]; then
			_proc "installing NGINX..."
			dnf -qy module disable php
			dnf -qy module disable nginx
			dnf -qy install http://nginx.org/packages/centos/8/x86_64/RPMS/nginx-1.20.1-1.el8.ngx.x86_64.rpm
			dnf -qy install nginx
			systemctl enable nginx
			systemctl start nginx
			HTTP="80,443"
			_openPort "$HTTP"
			_success "NGINX successfully installed!"
		else
			_warn "NGINX is already installed!"
		fi
	fi

	if [ "${_CMD}" = "cfg" ]; then
		which nginx &>/dev/null
		if [ $? -ne 1 ]; then
			if [ "${arg[0]}" ]; then
				_DOMAIN="${arg[0]}"
			else
				_DOMAIN="domain.tld"
			fi
			_proc "installing the nginx.conf..."
			_nginx_eof
			systemctl restart nginx
			_success "nginx.conf successfully installed!"
		else
			_warn "NGINX is not installed!"
		fi
	fi
}

_ipt() {
	_proc "installing the iptables rules..."
	systemctl stop iptables
	curl -s $_SRC/iptables.sh | sh
	systemctl start iptables
	_success "iptables rules successfully installed!"
}

_rmipv6() {
	_proc "Removing the IPv6 interface..."
	_GRUBFILE=/etc/default/grub
	grep -Eq "ipv6.disable" $_GRUBFILE || sed -i 's/^GRUB_CMDLINE_LINUX="/&ipv6.disable=1 /' $_GRUBFILE
	grep -Eq "ipv6.disable=0" $_GRUBFILE | sed -i 's/ipv6.disable=0/ipv6.disable=1/' $_GRUBFILE
	grub2-mkconfig -o /boot/grub2/grub.cfg &>/dev/null
	_success "IPv6 interface successfully Removed!"
}

install() {
	if [ -z "$1" ]; then
		_warn "Usage: build.sh --${_CMD} -i XXX[.../] YYY[.../.../] ZZZ[//.../] QQQ"
		return 1
	fi

	for i in ${1//,/ }; do
		_params=$(echo "$i" | \grep -Po '(?<=\[).*(?=\])')
		arg=(${_params//\// })
		for j in "${!arg[@]}"; do
			:
		done
		_i=$(echo "_$i" | sed 's/\[.*]//')
		$_i 2>/dev/null || _err "Unknown : ${_i:1}"
	done
}

showhelp() {
	__cyan "Usage: build.sh <command> ... [parameters ...]
Commands:
  -h, --help                        Show this help message.
  --pkg                             Install Packages from Repositories.
  --cfg                             Install Сonfiguration Settings.
  --rm-ipv6                         Remove IPv6 from interface.
  --ipt                             Install iptables rules.
Parameters:
  -i <...[.../]>                    Which package / configuration to install and, 
                                    if necessary, set the parameters in [.../]
                                    See: $_SRC" >&2
	printf "\n" >&2
}

_process() {
	_CMD=""
	_i=""
	_HOST=$(hostname -I | awk '{ print $1 }')
	_TIMEZONE=$(timedatectl | awk '/Time zone:/ {print $3}')
	_NUMCORE=$(cat /proc/cpuinfo | grep processor | wc -l)
	_AVG_NUMCORE=$(echo "$_NUMCORE / 2" | bc | cut -f 1 -d '.')
	_MEM_BYTES=$(awk '/MemTotal:/ { printf "%0.f", $2 * 1024 }' /proc/meminfo)
	_MEM_MB=$(awk '/MemTotal:/ { printf "%d\n", $2 / 1024 }' /proc/meminfo)
	_STACKSIZE=$(ulimit -s | awk '{ print $1 / 1024 }')

	while [ ${#} -gt 0 ]; do
		case "${1}" in
		--help | -h)
			showhelp
			return
			;;
		--psg)
			psg
			;;
		--pkg)
			_CMD="pkg"
			;;
		--cfg)
			_CMD="cfg"
			;;
		--rm-ipv6)
			_rmipv6
			return
			;;
		--ipt)
			_ipt
			return
			;;
		-i)
			_ivalue="$2"
			if [ "$_ivalue" ]; then
				if _startswith "$_ivalue" "-"; then
					_err "'$_ivalue' is not a valid ${_CMD} for parameter '$1'"
					return 1
				fi
				if [ -z "$_i" ]; then
					_i="$_ivalue"
				else
					_i="$_i,$_ivalue"
				fi
			fi
			shift
			;;
		*)
			_err "Unknown parameter : $1"
			return 1
			;;
		esac
		shift 1
	done

	if [ "${_CMD}" ]; then
		if ! _checkSudo; then
			_err "It seems that you are using sudo"
			return 1
		fi
	fi

	case "${_CMD}" in
	pkg) install "$_i" ;;
	cfg) install "$_i" ;;
	*)
		if [ "$_CMD" ]; then
			_err "Invalid command: $_CMD"
		fi
		showhelp
		return 1
		;;
	esac
}

main() {
	[ -z "$1" ] && showhelp && return
	if _startswith "$1" '-'; then _process "$@"; else
		_err "Invalid command: $@"
		showhelp
	fi
}

main "$@"
