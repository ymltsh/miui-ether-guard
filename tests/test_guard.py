import pathlib,subprocess,tempfile,json,shutil,sys
import os
ROOT=pathlib.Path(__file__).resolve().parents[1]
BUILD=ROOT/'build'
BUILD.mkdir(exist_ok=True)
base=ROOT/'module'
shell=os.environ.get('GUARD_TEST_SHELL') or shutil.which('sh')
if not shell: raise SystemExit('Set GUARD_TEST_SHELL to a POSIX sh executable')
guard=(base/'guard.sh').read_text()
cases={
 'never_armed':(['OFF']*20,0),
 'healthy':(['ON']*10,0),
 'stopped':(['ON']+['OFF']*4,1),
 'recovered':(['ON']+['OFF']*3+['ON']*5,1),
 'transient':(['ON','OFF','OFF','ON'],0),
 'unknown':(['ON']+['UNKNOWN']*20,0),
 'absent_reconnect':(['ON','GONE','GONE']+['OFF']*4,1),
 'long_absence':(['ON']+['GONE']*14+['OFF']*4,0),
 'different_adapter':(['ON']+['OTHER']*8,0),
 'carrier_down':(['ON']+['DOWN']*15+['OFF']*4,0),
 'multiple':(['ON']+['MULTI']*8,2),
 'paused':(['ON']+['PAUSE']*10,0),
 'retry_limit':(['ON']+['OFF']*115,6),
 'history_not_state':(['ON']+['HISTORY']*8,2),
 'error_state':(['ON']+['ERROR']*12,0),
 'preflight_recovers':(['ON']+['RACE']*10,0),
 'pause_at_preflight':(['ON']+['PAUSE_RACE']*8,0),
 'module_removed':(['ON']+['REMOVED']*8,0),
 'auto_boot':(['OFF']*4,1),
 'auto_any_adapter':(['OTHER']*12,3),
 'auto_reconnect_late':(['GONE']*15+['OFF']*4,1),
 'auto_no_carrier':(['DOWN']*15,3),
 'auto_paused':(['PAUSE']*12,0),
 'auto_retry_limit':(['OFF']*180,6),
 'auto_linkup_reset':(['DOWN']*120+['OFF']*4,7),
}
results=json.loads((BUILD/'test-results.json').read_text()) if len(sys.argv)>1 and (BUILD/'test-results.json').exists() else []
for name,(stages,expected) in cases.items():
 if len(sys.argv)>1 and name not in sys.argv[1:]: continue
 folder=pathlib.Path(tempfile.mkdtemp(prefix='guard-',dir=str(BUILD)))
 try:
  shutil.copy(base/'lib.sh',folder/'lib.sh')
  shutil.copy(base/'module.prop',folder/'module.prop')
  if name.startswith('auto_'): (folder/'auto.enabled').touch()
  if name=='auto_paused': (folder/'pause').touch()
  (folder/'stages').write_text('\n'.join(stages)+'\n')
  mocks=r'''
idx=1
stage() { sed -n "${idx}p" "$MODDIR/stages"; }
test_getprop() { echo 1; }
now_seconds() { echo $((idx * 10)); }
usb_candidates() {
 case "$(stage)" in GONE) ;; MULTI) printf 'eth0\neth1\n' ;; *) echo eth0 ;; esac
}
identity() { case "$(stage)" in OTHER) echo other ;; *) echo same ;; esac; }
auto_matches() { [ "$(stage)" != OTHER ]; }
cat() {
 case "$1" in /sys/class/net/*/carrier)
   case "$(stage)" in DOWN) echo 0 ;; *) echo 1 ;; esac ;;
 *) command cat "$@" ;; esac
}
helper() { [ "$1" = probe ] && return 0; echo "$idx" >> "$MODDIR/calls"; return 3; }
test_dump() {
 echo 'Tethering:'; echo '  Tether state:'
 case "$(stage)" in
 ON) echo '    eth0 - TetheredState - lastError = 0' ;;
 UNKNOWN) echo 'invalid format'; return 0 ;;
 ERROR) echo '    eth0 - AvailableState - lastError = 6' ;;
 HISTORY) ;; 
 RACE) if [ -f "$MODDIR/run/preflight.tmp" ]; then echo '    eth0 - TetheredState - lastError = 0'; else echo '    eth0 - AvailableState - lastError = 0'; fi ;;
 PAUSE_RACE) echo '    eth0 - AvailableState - lastError = 0'; [ -f "$MODDIR/run/preflight.tmp" ] && touch "$MODDIR/pause" ;;
 *) echo '    eth0 - AvailableState - lastError = 0' ;;
 esac
 echo '    Upstream wanted: false'
 echo '  Log:'; echo '2026-10-14 eth0 - TetheredState - lastError = 0'
}
timeout() { shift; "$@"; }
sleep() {
 idx=$((idx + 1))
 [ "$(stage)" = PAUSE ] && touch "$MODDIR/pause"
 [ "$(stage)" = REMOVED ] && rm -f "$MODDIR/module.prop"
 [ "$idx" -gt STAGECOUNT ] && touch "$MODDIR/disable"
 return 0
}
'''.replace('STAGECOUNT',str(len(stages)))
  stage_builtin='stage() { case "$idx" in\n'+''.join(f'{i}) echo {value} ;;\n' for i,value in enumerate(stages,1))+'*) echo END ;;\nesac; }\n'
  mocks += stage_builtin
  code=guard.replace('/system/bin/getprop','test_getprop').replace('/system/bin/dumpsys','test_dump')
  code=code.replace('flock -n 9', 'flock() { return 0; }\nflock -n 9',1)
  code=code.replace('while [ "$(test_getprop sys.boot_completed)"',mocks+'\nwhile [ "$(test_getprop sys.boot_completed)"',1)
  (folder/'guard.sh').write_text(code,newline='\n')
  p=subprocess.run([shell,str(folder/'guard.sh').replace('\\','/')],capture_output=True,timeout=120)
  calls=(folder/'calls').read_text().splitlines() if (folder/'calls').exists() else []
  assert p.returncode==0,(name,p.stderr.decode())
  assert len(calls)==expected,(name,calls,(folder/'run/guard.log').read_text() if (folder/'run/guard.log').exists() else 'no log',p.stderr.decode())
  if name=='retry_limit': assert [int(x) for x in calls]==[4,7,13,25,49,109],calls
  results=[r for r in results if r['case']!=name]
  results.append({'case':name,'start_requests':len(calls),'passed':True})
  print('PASS',name,flush=True)
 finally:
  shutil.rmtree(folder)
print(json.dumps(results,indent=2))
(BUILD/'test-results.json').write_text(json.dumps(results,indent=2))
