#!/system/bin/sh
MODDIR=${0%/*}
if [ -f "$MODDIR/pause" ]; then
  rm -f "$MODDIR/pause"
  echo "Recovery resumed. Any USB Ethernet adapter can trigger native tethering."
else
  touch "$MODDIR/pause"
  echo "Recovery paused. Wait 10 seconds before manually switching sharing off."
fi
