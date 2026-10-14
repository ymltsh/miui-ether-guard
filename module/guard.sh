#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/lib.sh"
umask 077
RUNDIR="$MODDIR/run"
mkdir -p "$RUNDIR"
# BusyBox flock lock is released by the kernel, including after a crash/reboot.
exec 9>"$RUNDIR/lock"
flock -n 9 || exit 0
log() {
  [ -f "$RUNDIR/guard.log" ] && [ "$(wc -c < "$RUNDIR/guard.log")" -gt 131072 ] && mv -f "$RUNDIR/guard.log" "$RUNDIR/guard.log.1"
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*" >> "$RUNDIR/guard.log"
}
helper() {
  timeout 20 /system/bin/env CLASSPATH="$MODDIR/helper.jar" /system/bin/app_process /system/bin local.etherguard.EtherGuard "$1"
}
disarm() {
  [ -n "$armed" ] && log "DISARM $armed: $1"
  armed=; key=; misses=0; attempts=0; wait_ticks=0; gap_since=0
}
now_seconds() { cut -d. -f1 /proc/uptime; }
hold_gap() {
  misses=0
  [ -z "$armed" ] && return
  if [ "$gap_since" -eq 0 ]; then gap_since=$(now_seconds); log "HOLD $armed: link unavailable; grace=120s"; fi
  [ "$(( $(now_seconds) - gap_since ))" -ge 120 ] && disarm "link absent for 120s"
}
armed=; key=; misses=0; attempts=0; wait_ticks=0; gap_since=0; auto_blocked=0
observe=0
[ "$1" = "--observe" ] && observe=1
trap 'log "daemon exit"; exit 0' TERM INT
while [ "$(/system/bin/getprop sys.boot_completed)" != 1 ]; do
  [ -f "$MODDIR/module.prop" ] || exit 0
  [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ] && exit 0
  sleep 5
done
helper probe > "$RUNDIR/probe.txt" 2>&1
if [ "$?" != 0 ]; then log "UNSUPPORTED: see run/probe.txt; no changes made"; exit 0; fi
log "daemon started; any USB Ethernet auto-restore enabled when auto.enabled exists"
last_present=0; last_carrier=; last_key=
while [ -f "$MODDIR/module.prop" ] && [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]; do
  if [ -f "$MODDIR/pause" ]; then
    disarm paused
    auto_blocked=0
    sleep 10; continue
  fi
  candidates=$(usb_candidates)
  count=$(printf '%s\n' "$candidates" | awk 'NF {n++} END {print n+0}')
  if [ "$count" -eq 0 ]; then last_present=0; hold_gap; sleep 10; continue; fi
  # Native Android chooses its default Ethernet interface; never configure per-port NAT.
  iface=$(printf '%s\n' "$candidates" | head -n 1)
  current=$(identity "$iface")
  carrier=$(cat "/sys/class/net/$iface/carrier" 2>/dev/null)
  if [ "$last_present" -eq 0 ] || [ "$last_key" != "$current" ] || { [ "$last_carrier" != 1 ] && [ "$carrier" = 1 ]; }; then
    auto_blocked=0
  fi
  last_present=1; last_key=$current; last_carrier=$carrier
  # Preserve observed intent for a short same-adapter USB reset, never start while absent.
  if [ ! -f "$MODDIR/auto.enabled" ] && [ "$carrier" != 1 ]; then
    hold_gap; sleep 10; continue
  fi
  if [ -n "$armed" ] && { [ "$armed" != "$iface" ] || [ "$key" != "$current" ]; }; then
    disarm "adapter identity changed"
  fi
  if [ "$gap_since" -gt 0 ]; then
    if [ "$(( $(now_seconds) - gap_since ))" -ge 120 ]; then
      disarm "reconnect grace expired"
    else
      log "same adapter returned within grace"; gap_since=0
    fi
  fi
  if [ -f "$MODDIR/auto.enabled" ]; then
    if [ -z "$armed" ] && [ "$auto_blocked" -eq 0 ]; then
      armed=$iface; key=$current; log "AUTO_ARM USB Ethernet $iface $key"
    fi
  fi
  if timeout 12 /system/bin/dumpsys tethering > "$RUNDIR/state.tmp" 2>&1; then
    state=$(tether_state "$iface" "$RUNDIR/state.tmp")
  else state=UNKNOWN; fi
  case "$state" in
    ON)
      if [ -z "$armed" ]; then armed=$iface; key=$current; log "ARM $iface $key"; fi
      misses=0; attempts=0; wait_ticks=0; auto_blocked=0 ;;
    OFF|ABSENT)
      if [ -n "$armed" ]; then
        misses=$((misses + 1))
        if [ "$wait_ticks" -gt 0 ]; then wait_ticks=$((wait_ticks - 1)); fi
        if [ "$misses" -ge 3 ] && [ "$wait_ticks" -eq 0 ]; then
          # Recheck pause, carrier and identity immediately before requesting start.
          if [ -f "$MODDIR/pause" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ] ||
             ! usb_candidates | grep -Fxq "$iface" || [ "$(identity "$iface")" != "$key" ]; then
            disarm "preflight changed"; sleep 10; continue
          fi
          # Sharing may have resumed between polls; validate the current section again.
          if ! timeout 12 /system/bin/dumpsys tethering > "$RUNDIR/preflight.tmp" 2>&1; then
            misses=0; sleep 10; continue
          fi
          fresh=$(tether_state "$iface" "$RUNDIR/preflight.tmp")
          case "$fresh" in OFF|ABSENT) ;; *) misses=0; sleep 10; continue ;; esac
          if [ -f "$MODDIR/pause" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ] ||
             [ "$(usb_candidates | head -n 1)" != "$iface" ] ||
             [ "$(identity "$iface")" != "$key" ]; then
            disarm "final preflight changed"; sleep 10; continue
          fi
          attempts=$((attempts + 1))
          cp "$RUNDIR/state.tmp" "$RUNDIR/before-recovery.txt"
          log "RECOVER attempt=$attempts iface=$iface state=$state"
          if [ "$observe" -eq 1 ]; then
            log "OBSERVE_ONLY: start skipped"; rc=0
          else
            helper start > "$RUNDIR/last-start.txt" 2>&1
            rc=$?
          fi
          log "native start returned=$rc; next polls verify actual TetheredState"
          case "$attempts" in 1) wait_ticks=3 ;; 2) wait_ticks=6 ;; 3) wait_ticks=12 ;; 4) wait_ticks=24 ;; *) wait_ticks=60 ;; esac
          if [ "$attempts" -ge 6 ]; then
            log "CIRCUIT_OPEN: six attempts; reconnect adapter, link up, pause/resume or reboot to retry"
            auto_blocked=1
            disarm "retry limit"
          fi
        fi
      fi ;;
    *)
      # Failed/changed dumpsys format must never be interpreted as stopped.
      misses=0 ;;
  esac
  sleep 10
done
log "disabled/removed; daemon exit without stopping any native tethering"
