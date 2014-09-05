#!/bin/sh
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh
#
# Format:
#	ip=[dhcp|on|any]
#
#	ip=<interface>:[dhcp|on|any]
#
#	ip=<client-IP-number>:<server-id>:<gateway-IP-number>:<netmask>:<client-hostname>:<interface>:[dhcp|on|any|none|off]
#
# When supplying more than only ip= line, <interface> is mandatory and
# bootdev= must contain the name of the primary interface to use for
# routing,dns,dhcp-options,etc.
#

. /lib/dracut-lib.sh

# Check if ip= lines should be used
if getarg ip= >/dev/null ; then
    if [ -z "$netroot" ] ; then
	echo "Warning: No netboot configured, ignoring ip= lines"
	return;
    fi
fi

# Don't mix BOOTIF=macaddr from pxelinux and ip= lines
getarg ip= >/dev/null && getarg BOOTIF= >/dev/null && \
    die "Mixing BOOTIF and ip= lines is dangerous"

# No more parsing stuff, BOOTIF says everything
[ -n "$(getarg BOOTIF)" ] && return

if [ -n "$netroot" ] && [ -z "$(getarg ip=)" ] ; then
    # No ip= argument(s) for netroot provided, defaulting to DHCP
    return;
fi

# Count ip= lines to decide whether we need bootdev= or not
if [ "$netroot" = "dhcp" ] || [ "$netroot" = "dhcp6" ]; then
    if [ -z "$NEEDBOOTDEV" ] ; then
	local count=0
	for p in $(getargs ip=); do
	    count=$(( $count + 1 ))
	done
	[ $count -gt 1 ] && NEEDBOOTDEV=1
    fi
fi

# If needed, check if bootdev= contains anything usable
BOOTDEV=$(getarg bootdev=)

if [ -n "$NEEDBOOTDEV" ] ; then
    [ -z "$BOOTDEV" ] && warn "Please supply bootdev argument for multiple ip= lines"
fi

if [ "ibft" = "$(getarg ip=)" ]; then
    modprobe iscsi_ibft
    num=0
    (
	for iface in /sys/firmware/ibft/ethernet*; do
        unset ifname_mac
        unset ifname_if
        unset dhcp
        unset ip
        unset gw
        unset mask
        unset hostname
        unset vlan
	    [ -e ${iface}/mac ] || continue
            ifname_mac=$(read a < ${iface}/mac; echo $a)
	    [ -z "$ifname_mac" ] && continue
            unset dev
            for ifname in $(getargs ifname=); do
		if strstr "$ifname" "$ifname_mac"; then
		    dev=${ifname%%:*}
                    break
                fi
	    done
            if [ -z "$dev" ]; then
		ifname_if=ibft$num
		num=$(( $num + 1 ))
		echo "ifname=$ifname_if:$ifname_mac"
		dev=$ifname_if
	    fi

	    [ -e ${iface}/dhcp ] && dhcp=$(read a < ${iface}/dhcp; echo $a)
	    if [ -n "$dhcp" ]; then
		echo "ip=$dev:dhcp"
	    else
		[ -e ${iface}/ip-addr ] && ip=$(read a < ${iface}/ip-addr; echo $a)
		[ "$ip" = "0.0.0.0" ] && unset ip
		[ -e ${iface}/gateway ] && gw=$(read a < ${iface}/gateway; echo $a)
		[ -e ${iface}/subnet-mask ] && mask=$(read a < ${iface}/subnet-mask; echo $a)
		[ -e ${iface}/hostname ] && hostname=$(read a < ${iface}/hostname; echo $a)
		[ -n "$ip" ] && echo "ip=$ip::$gw:$mask:$hostname:$dev:none"
	    fi

            if [ -e ${iface}/vlan ]; then
		vlan=$(read a < ${iface}/vlan; echo $a)
                if [ "$vlan" -ne "0" ]; then
                    case "$vlan" in
                        [0-9]*)
                            echo "vlan=$dev.$vlan:$dev"
                            ;;
                        *)
                            echo "vlan=$vlan:$dev"
                            ;;
                    esac
                fi
            fi
	done
    ) >> /etc/cmdline
    # reread cmdline
    unset CMDLINE
fi

# Check ip= lines
# XXX Would be nice if we could errorcheck ip addresses here as well
for p in $(getargs ip=); do
    ip_to_var $p

    # skip ibft
    [ "$autoconf" = "ibft" ] && continue

    # We need to have an ip= line for the specified bootdev
    [ -n "$NEEDBOOTDEV" ] && [ "$dev" = "$BOOTDEV" ] && BOOTDEVOK=1

    # Empty autoconf defaults to 'dhcp'
    if [ -z "$autoconf" ] ; then
	warn "Empty autoconf values default to dhcp"
	autoconf="dhcp"
    fi
    OLDIFS="$IFS"
    IFS=,
    set -- $autoconf
    IFS="$OLDIFS"
    for autoconf in "$@"; do
        # Error checking for autoconf in combination with other values
        case $autoconf in
	    error) die "Error parsing option 'ip=$p'";;
	    bootp|rarp|both) die "Sorry, ip=$autoconf is currenty unsupported";;
	    none|off) \
	        [ -z "$ip" ] && \
		die "For argument 'ip=$p'\nValue '$autoconf' without static configuration does not make sense"
	        [ -z "$mask" ] && \
		    die "Sorry, automatic calculation of netmask is not yet supported"
	        ;;
	    auto6);;
	    dhcp|dhcp6|on|any) \
	        [ -n "$NEEDBOOTDEV" ] && [ -z "$dev" ] && \
	        die "Sorry, 'ip=$p' does not make sense for multiple interface configurations"
	        [ -n "$ip" ] && \
		    die "For argument 'ip=$p'\nSorry, setting client-ip does not make sense for '$autoconf'"
	        ;;
	    *) die "For argument 'ip=$p'\nSorry, unknown value '$autoconf'";;
        esac
        _part=${_part%,*}
    done

    if [ -n "$dev" ] ; then
        # We don't like duplicate device configs
	if [ -n "$IFACES" ] ; then
	    for i in $IFACES ; do
		[ "$dev" = "$i" ] && warn "For argument 'ip=$p'\nDuplication configurations for '$dev'"
	    done
	fi
	# IFACES list for later use
	IFACES="$IFACES $dev"
    fi

    # Do we need to check for specific options?
    if [ -n "$NEEDDHCP" ] || [ -n "$DHCPORSERVER" ] ; then
	# Correct device? (Empty is ok as well)
	[ "$dev" = "$BOOTDEV" ] || continue
	# Server-ip is there?
	[ -n "$DHCPORSERVER" ] && [ -n "$srv" ] && continue
	# dhcp? (It's simpler to check for a set ip. Checks above ensure that if
	# ip is there, we're static
	[ -z "$ip" ] && continue
	# Not good!
	die "Server-ip or dhcp for netboot needed, but current arguments say otherwise"
    fi

done

# This ensures that BOOTDEV is always first in IFACES
if [ -n "$BOOTDEV" ] && [ -n "$IFACES" ] ; then 
    IFACES="${IFACES%$BOOTDEV*} ${IFACES#*$BOOTDEV}"
    IFACES="$BOOTDEV $IFACES"
fi

# Store BOOTDEV and IFACES for later use
[ -n "$BOOTDEV" ] && echo $BOOTDEV > /tmp/net.bootdev
[ -n "$IFACES" ]  && echo $IFACES > /tmp/net.ifaces

# We need a ip= line for the configured bootdev= 
[ -n "$NEEDBOOTDEV" ] && [ -z "$BOOTDEVOK" ] && die "Bootdev Argument '$BOOTDEV' not found"
