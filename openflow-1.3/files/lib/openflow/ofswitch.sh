#!/bin/sh
# Copyright (C) 2006 OpenWrt.org

#DEBUG="echo"

add_ofswitch_datapath() {
	local config="$1"
	local ofports
	local dpports
	local dp
	local mode
	local dpid

	config_get ofports "$config" ofports
	config_get dp "$config" dp
	config_get mode "$config" mode
	config_get dpid "$config" dpid


	dpports=`echo "$ofports" | tr ' ' ','`
	echo "$dpports"

	[ -n "$dpports" ] && {
		if [[ "$mode" == "inband" ]]
		then
			echo "Configuring OpenFlow switch for inband control"
 			[ -n "$dpid" ] && {
				ofdatapath ptcp:6634 -i "$dpports" --no-slicing --local-port=tap:tap0 --pidfile -d "$dpid" &
			} || {
				ofdatapath ptcp:6634 -i "$dpports" --no-slicing --local-port=tap:tap0 --pidfile &
			}
		else
			echo "Configuring OpenFlow switch for out-of-band control"
			[ -n "$dpid" ] && {
				ofdatapath ptcp:6634 -i "$dpports" --no-slicing  --no-local-port --pidfile -d "$dpid" &
			} || {
				ofdatapath ptcp:6634 -i "$dpports" --no-slicing  --no-local-port --pidfile &
			}
		fi
	}
}

setup_ofswitch() {
	local config="$1"

	add_ofswitch_datapath "$config"
}
		
