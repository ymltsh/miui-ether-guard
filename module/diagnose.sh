#!/system/bin/sh
MODDIR=${0%/*}
umask 077
mkdir -p "$MODDIR/run"
{
  date
  /system/bin/getprop ro.product.model
  /system/bin/getprop ro.build.version.release
  /system/bin/getprop ro.build.version.incremental
  /system/bin/getprop ro.miui.ui.version.name
  /system/bin/getenforce
  timeout 10 /system/bin/cmd tethering help
  timeout 12 /system/bin/dumpsys tethering
  /system/bin/ip -br link || /system/bin/ip link
  timeout 10 /system/bin/dumpsys ethernet
  /system/bin/getprop sys.usb.config
  /system/bin/getprop sys.usb.state
  for node in /sys/class/net/*; do
    echo "NET ${node##*/}"
    readlink -f "$node/device"
    readlink -f "$node/device/driver"
    cat "$node/carrier" 2>/dev/null
  done
  timeout 20 /system/bin/env CLASSPATH="$MODDIR/helper.jar" /system/bin/app_process /system/bin local.etherguard.EtherGuard probe
} > "$MODDIR/run/diagnostics.txt" 2>&1
echo "$MODDIR/run/diagnostics.txt"
