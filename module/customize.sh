#!/system/bin/sh
[ "$API" -ge 30 ] || abort "Android 11+ required"
# Preserve a previous deliberate pause on upgrades.
[ -f /data/adb/modules/miui_ether_guard/pause ] && touch "$MODPATH/pause"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for script in service.sh guard.sh action.sh diagnose.sh uninstall.sh; do
  set_perm "$MODPATH/$script" 0 0 0755
done
ui_print "Ethernet Guard: automatic native tethering after reboot."
ui_print "Any physical USB Ethernet adapter can trigger automatic tethering."
ui_print "Use module Action to pause/resume before manually switching sharing off."
