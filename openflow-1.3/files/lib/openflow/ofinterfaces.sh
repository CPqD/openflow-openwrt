#!/bin/sh
# Copyright (C) 2006 OpenWrt.org

# DEBUG="echo"

find_config() {
	local iftype device iface ifaces ifn
	for ifn in $ofinterfaces; do
		config_get iftype "$ifn" type
		config_get iface "$ifn" ifname
		config_get device "$ifn" device
		for ifc in $device $iface $ifaces; do
			[ ."$ifc" = ."$1" ] && {
				echo "$ifn"
				return 0
			}
		done
	done

	return 1;
}

scan_ofinterfaces() {
	local cfgfile="$1"
	local mode iftype iface ifname device
	ofswitches=
	config_cb() {
		case "$1" in
			ofswitch)
				config_set "$2" auto 1
			;;
		esac
		config_get iftype "$CONFIG_SECTION" TYPE
		case "$iftype" in
			ofswitch)
				config_get proto "$CONFIG_SECTION" proto
				append ofinterfaces "$CONFIG_SECTION"
				config_get iftype "$CONFIG_SECTION" type
				config_get ifname "$CONFIG_SECTION" ifname
				config_get device "$CONFIG_SECTION" device
				config_set "$CONFIG_SECTION" device "${device:-$ifname}"
				( type "scan_$proto" ) >/dev/null 2>/dev/null && eval "scan_$proto '$CONFIG_SECTION'"
			;;
		esac
	}
	config_load "${cfgfile:-openflow}"
}

# sort the device list, drop duplicates
sort_list() {
	local arg="$*"
	(
		for item in $arg; do
			echo "$item"
		done
	) | sort -u
}

# Create the ofswitch, if necessary.
# Return status 0 indicates that the setup_ofinterface() call should continue
# Return status 1 means that everything is set up already.

prepare_ofinterface() {
	local iface="$1"
	local config="$2"
	local vifmac="$3"
	local proto

	ifconfig "$iface" 2>/dev/null >/dev/null && {
		config_get proto "$config" proto

		[ "$proto" = none ] || ifconfig "$iface" 0.0.0.0

		# Change ofinterface MAC address if requested
		[ -n "$vifmac" ] && {
			ifconfig "$iface" down
			ifconfig "$iface" hw ether "$vifmac" up
		}
	}

	return 0
}

set_ofinterface_ifname() {
	local config="$1"
	local ifname="$2"

	config_get device "$1" device
	uci_set_state openflow "$config" ifname "$ifname"
	uci_set_state openflow "$config" device "$device"
}

setup_ofinterface_none() {
	env -i ACTION="ifup" INTERFACE="$2" DEVICE="$1" PROTO=none /sbin/hotplug-call "ofiface" &
}

setup_ofinterface_static() {
	local iface="$1"
	local config="$2"

	config_get ipaddr "$config" ipaddr
	config_get netmask "$config" netmask
	config_get ip6addr "$config" ip6addr
	[ -z "$ipaddr" -o -z "$netmask" ] && [ -z "$ip6addr" ] && return 1
	
	config_get gateway "$config" gateway
	config_get ip6gw "$config" ip6gw
	config_get dns "$config" dns
	config_get bcast "$config" broadcast
	
	[ -z "$ipaddr" ] || $DEBUG ifconfig "$iface" "$ipaddr" netmask "$netmask" broadcast "${bcast:-+}"
	[ -z "$ip6addr" ] || $DEBUG ifconfig "$iface" add "$ip6addr"
	[ -z "$gateway" ] || $DEBUG route add default gw "$gateway" dev "$iface"
	[ -z "$ip6gw" ] || $DEBUG route -A inet6 add default gw "$ip6gw" dev "$iface"
	[ -z "$dns" ] || {
		for ns in $dns; do
			grep "$ns" /tmp/resolv.conf.auto 2>/dev/null >/dev/null || {
				echo "nameserver $ns" >> /tmp/resolv.conf.auto
			}
		done
	}

	env -i ACTION="ifup" INTERFACE="$config" DEVICE="$iface" PROTO=static /sbin/hotplug-call "ofiface" &
}

setup_ofinterface() {
	local iface="$1"
	local config="$2"
	local vifmac="$4"
	local proto
	local macaddr

	[ -n "$config" ] || {
		config=$(find_config "$iface")
		[ "$?" = 0 ] || return 1
	}
	proto="${3:-$(config_get "$config" proto)}"

	prepare_ofinterface "$iface" "$config" "$vifmac" || return 0

	# Openflow switch settings
	config_get mtu "$config" mtu
	config_get macaddr "$config" macaddr
	grep "$iface:" /proc/net/dev > /dev/null && {
		[ -n "$macaddr" ] && $DEBUG ifconfig "$iface" down
		$DEBUG ifconfig "$iface" ${macaddr:+hw ether "$macaddr"} ${mtu:+mtu $mtu} up
	}
	set_ofinterface_ifname "$config" "$iface"

	pidfile="/var/run/$iface.pid"
	case "$proto" in
		static)
			setup_ofinterface_static "$iface" "$config"
		;;
		dhcp)
			# prevent udhcpc from starting more than once
			lock "/var/lock/dhcp-$iface"
			pid="$(cat "$pidfile" 2>/dev/null)"
			if [ -d "/proc/$pid" ] && grep udhcpc "/proc/${pid}/cmdline" >/dev/null 2>/dev/null; then
				lock -u "/var/lock/dhcp-$iface"
			else

				config_get ipaddr "$config" ipaddr
				config_get netmask "$config" netmask
				config_get hostname "$config" hostname
				config_get proto1 "$config" proto
				config_get clientid "$config" clientid

				[ -z "$ipaddr" ] || \
					$DEBUG ifconfig "$iface" "$ipaddr" ${netmask:+netmask "$netmask"}

				# don't stay running in background if dhcp is not the main proto on the ofinterface (e.g. when using pptp)
				[ ."$proto1" != ."$proto" ] && dhcpopts="-n -q"
				$DEBUG eval udhcpc -t 0 -i "$iface" ${ipaddr:+-r $ipaddr} ${hostname:+-H $hostname} ${clientid:+-c $clientid} -b -p "$pidfile" ${dhcpopts:- -R &}
				lock -u "/var/lock/dhcp-$iface"
			fi
		;;
		none)
			setup_ofinterface "$iface" "$config"
		;;
		*)
			if ( eval "type setup_ofinterface_$proto" ) >/dev/null 2>/dev/null; then
				eval "setup_ofinterface_$proto '$iface' '$config' '$proto'" 
			else
				echo "Openflow interface type $proto not supported."
				return 1
			fi
		;;
	esac
	[ "$proto" = none ] || {
		for ifn in `ifconfig | grep "^$iface:" | awk '{print $1}'`; do
			ifconfig "$ifn" down
		done
	}
	echo "$iface $config"
}
