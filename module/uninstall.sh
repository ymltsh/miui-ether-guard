#!/system/bin/sh
MODDIR=${0%/*}
touch "$MODDIR/disable"
# No iptables/DHCP/property/settings changes to undo. Daemon checks this flag.
