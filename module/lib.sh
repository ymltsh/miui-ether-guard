#!/system/bin/sh
# Match only the CURRENT tether-state section, never historical log lines.
tether_state() {
  awk -v iface="$1" '
    /^[[:space:]]*Tether state:/ {section=1; header=1; next}
    section && /^[[:space:]]*Upstream wanted:/ {section=0; footer=1}
    section && $1==iface && $2=="-" {state=$3; error=$NF; found=1}
    END {
      if (!header || !footer) print "UNKNOWN";
      else if (!found) print "ABSENT";
      else if (state=="TetheredState" && error=="0") print "ON";
      else if (state=="AvailableState" && error=="0") print "OFF";
      else print "UNKNOWN";
    }' "$2"
}
# One physical USB Ethernet adapter only. Exclude gadget and virtual interfaces.
usb_candidates() {
  for node in /sys/class/net/*; do
    name=${node##*/}
    case "$name" in eth[0-9]*|enx*|usb[0-9]*) ;; *) continue ;; esac
    [ "$(cat "$node/type" 2>/dev/null)" = 1 ] || continue
    device=$(readlink -f "$node/device" 2>/dev/null)
    case "$device" in */usb*/*) ;; *) continue ;; esac
    driver=$(readlink -f "$node/device/driver" 2>/dev/null)
    case "${driver##*/}" in rndis*|g_*|*gadget*) continue ;; esac
    [ -n "$driver" ] || continue
    printf '%s\n' "$name"
  done
}
identity() {
  printf '%s:%s\n' "$(readlink -f "/sys/class/net/$1/device")" "$(cat "/sys/class/net/$1/address")"
}
auto_matches() {
  [ -s "$MODDIR/auto.mac" ] && [ -s "$MODDIR/auto.product" ] && [ -s "$MODDIR/auto.driver" ] || return 1
  [ "$(cat "/sys/class/net/$1/address" 2>/dev/null)" = "$(cat "$MODDIR/auto.mac")" ] || return 1
  product=$(awk -F= '$1=="PRODUCT" {print $2}' "/sys/class/net/$1/device/uevent" 2>/dev/null)
  [ "$product" = "$(cat "$MODDIR/auto.product")" ] || return 1
  driver=$(readlink -f "/sys/class/net/$1/device/driver" 2>/dev/null)
  [ "${driver##*/}" = "$(cat "$MODDIR/auto.driver")" ]
}
