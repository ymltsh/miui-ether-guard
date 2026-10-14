#!/system/bin/sh
MODDIR=${0%/*}
# Magisk late_start is nonblocking. The daemon never runs in post-fs-data.
/data/adb/magisk/busybox sh "$MODDIR/guard.sh" >/dev/null 2>&1 &
