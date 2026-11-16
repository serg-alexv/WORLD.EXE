"""Bounded process-exit recovery for the exact WORLD.EXE guardian task; no periodic work runs."""
from __future__ import annotations
import argparse, ctypes, json, os, sys, time
from ctypes import wintypes as w
from pathlib import Path
from common import GateError, RestartBudget, atomic, bounded_run, file_lock, load_config, log_event, read_json, utc
TASK='WORLD.EXE-LocalSupervisor'

def recovery_allowed(state, task_enabled=True):
    state=Path(state)
    return task_enabled and not (state/'stop.json').exists() and not read_json(state/'guardian.json',{}).get('circuit',False)

class ProcessExit:
    def __init__(self,pid):
        if os.name!='nt':raise GateError('native_windows_required')
        if type(pid) is not int or pid<=0:raise GateError('invalid_process_identity')
        self.k=ctypes.WinDLL('kernel32',use_last_error=True)
        self.k.OpenProcess.argtypes=[w.DWORD,w.BOOL,w.DWORD];self.k.OpenProcess.restype=w.HANDLE
        self.k.WaitForSingleObject.argtypes=[w.HANDLE,w.DWORD];self.k.WaitForSingleObject.restype=w.DWORD
        self.k.CloseHandle.argtypes=[w.HANDLE]
        self.handle=self.k.OpenProcess(0x100000,False,pid)
        if not self.handle:raise GateError('process_not_attachable')
    def exited(self,milliseconds=2000):
        value=self.k.WaitForSingleObject(self.handle,milliseconds)
        if value==0:return True
        if value==258:return False
        raise GateError('process_wait_failed')
    def close(self):
        if self.handle:self.k.CloseHandle(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*args):self.close()

def is_owned_guardian(pid,base):
    if type(pid) is not int or pid<=0:return False
    needle=str(Path(base)/'launch.py').replace("'","''")
    script=f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId={pid}'; if($p -and $p.Name -eq 'pythonw.exe' -and $p.CommandLine.Contains('{needle}')){{'owned'}}else{{'absent'}}"
    rc,out,_=bounded_run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],timeout=15)
    return rc==0 and out.strip()==b'owned'

def start_exact_task(cfg):
    base=Path(cfg['ops'])/'local-supervisor'
    exe=str(Path(cfg['python']).with_name('pythonw.exe')).replace("'","''")
    args=('-B "'+str(base/'launch.py')+'"').replace("'","''")
    script=f"""$ErrorActionPreference='Stop'; $t=Get-ScheduledTask -TaskName '{TASK}';
if(!$t.Settings.Enabled){{'disabled';exit 0}};
if(@($t.Actions).Count -ne 1 -or $t.Actions.Execute -ne '{exe}' -or $t.Actions.Arguments -ne '{args}'){{throw 'Task action identity changed'}};
if($t.State -eq 'Running'){{Stop-ScheduledTask -TaskName '{TASK}'}};
Start-ScheduledTask -TaskName '{TASK}';'started'
"""
    rc,out,_=bounded_run(['powershell.exe','-NoProfile','-NonInteractive','-Command',script],timeout=20)
    if rc:raise GateError('task_recovery_refused')
    return out.decode().strip()=='started'

def supervise(cfg):
    state=Path(cfg['state']);base=Path(cfg['ops'])/'local-supervisor'
    with file_lock(state/'recovery.lock'):
        saved=read_json(state/'recovery.json',{});budget=RestartBudget(saved.get('restart_times',[]))
        def receipt(phase,**extra):
            atomic(state/'recovery.json',{'utc':utc(),'pid':os.getpid(),'phase':phase,'restart_times':budget.times,**extra})
        if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
        # Two logon tasks can start concurrently: allow the primary's ordinary startup first.
        start=time.monotonic()
        while time.monotonic()-start<15:
            guardian=read_json(state/'guardian.json',{})
            if is_owned_guardian(guardian.get('guardian_pid'),base):break
            if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
            time.sleep(1)
        while recovery_allowed(state):
            guardian=read_json(state/'guardian.json',{});pid=guardian.get('guardian_pid')
            if is_owned_guardian(pid,base):
                receipt('waiting_for_process_exit',guardian_pid=pid);updated=time.monotonic()
                try:
                    with ProcessExit(pid) as process:
                        while not process.exited(2000):
                            if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
                            if time.monotonic()-updated>15:
                                receipt('waiting_for_process_exit',guardian_pid=pid);updated=time.monotonic()
                except GateError as e:
                    if str(e)!='process_not_attachable':raise
            if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
            # Another owner/OS restart may already have recovered it: never stop a new live guardian.
            current=read_json(state/'guardian.json',{}).get('guardian_pid')
            if current!=pid and is_owned_guardian(current,base):continue
            delay=budget.record(time.time())
            if delay is None:receipt('recovery_circuit_open',circuit=True);return 0
            receipt('restarting_guardian',old_guardian=pid,delay=delay);time.sleep(delay)
            current=read_json(state/'guardian.json',{}).get('guardian_pid')
            if is_owned_guardian(current,base):continue
            if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
            if not start_exact_task(cfg):receipt('task_disabled_by_operator');return 0
            log_event(state,'guardian_exit_recovery',old_guardian=pid,attempt=len(budget.times))
            deadline=time.monotonic()+20
            while time.monotonic()<deadline:
                current=read_json(state/'guardian.json',{}).get('guardian_pid')
                if current!=pid and is_owned_guardian(current,base):break
                if not recovery_allowed(state):receipt('operator_stopped_or_circuit');return 0
                time.sleep(1)
        receipt('operator_stopped_or_circuit');return 0

def main():
    sys.dont_write_bytecode=True
    p=argparse.ArgumentParser();p.add_argument('--config',required=True);p.add_argument('--config-hash',required=True);a=p.parse_args()
    return supervise(load_config(a.config,a.config_hash))
if __name__=='__main__':
    try:raise SystemExit(main())
    except GateError as e:print(json.dumps({'blocked':str(e)}));raise SystemExit(2)
