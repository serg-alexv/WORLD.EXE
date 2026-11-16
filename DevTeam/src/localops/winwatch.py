"""Native directory notifications and a Windows kill-on-close child job."""
from __future__ import annotations
import os, struct, threading, ctypes
from ctypes import wintypes as w
from common import GateError

class DirectoryWatch(threading.Thread):
    def __init__(self, path, callback):
        super().__init__(daemon=True,name='worldexe-directory-watch')
        self.path=str(path);self.callback=callback;self.stopping=threading.Event();self.handle=None
        self.ready=threading.Event();self.failure=None
    def run(self):
        k=ctypes.WinDLL('kernel32',use_last_error=True)
        k.CreateFileW.argtypes=[w.LPCWSTR,w.DWORD,w.DWORD,ctypes.c_void_p,w.DWORD,w.DWORD,w.HANDLE];k.CreateFileW.restype=w.HANDLE
        k.ReadDirectoryChangesW.argtypes=[w.HANDLE,ctypes.c_void_p,w.DWORD,w.BOOL,w.DWORD,ctypes.POINTER(w.DWORD),ctypes.c_void_p,ctypes.c_void_p]
        k.ReadDirectoryChangesW.restype=w.BOOL;k.CloseHandle.argtypes=[w.HANDLE]
        h=k.CreateFileW(self.path,1,7,None,3,0x02000000,None)
        if h==ctypes.c_void_p(-1).value:
            self.failure='watch_open_failed';self.ready.set();self.callback(None,'watch_error');return
        self.handle=h;buf=ctypes.create_string_buffer(32768);count=w.DWORD()
        self.ready.set()
        try:
            while not self.stopping.is_set():
                ok=k.ReadDirectoryChangesW(h,buf,len(buf),True,0x01|0x02|0x08|0x10,ctypes.byref(count),None,None)
                if self.stopping.is_set(): break
                if not ok:
                    self.failure='watch_read_failed';self.callback(None,'watch_error');break
                if count.value==0:
                    self.callback(None,'overflow');continue
                raw=buf.raw[:count.value];off=0
                while off+12<=len(raw):
                    nxt,action,n=struct.unpack_from('<III',raw,off)
                    if n%2 or off+12+n>len(raw):self.callback(None,'overflow');break
                    name=raw[off+12:off+12+n].decode('utf-16-le',errors='strict').replace('\\','/')
                    self.callback(name,'filesystem')
                    if not nxt:break
                    if nxt<12 or off+nxt>=len(raw):self.callback(None,'overflow');break
                    off+=nxt
        except Exception:
            self.failure='watch_decode_failed';self.callback(None,'watch_error')
        finally:
            self.handle=None;k.CloseHandle(h)
    def close(self):
        self.stopping.set()
        h=self.handle
        if h:
            k=ctypes.WinDLL('kernel32',use_last_error=True);k.CancelIoEx.argtypes=[w.HANDLE,ctypes.c_void_p]
            k.CancelIoEx(h,None)
        self.join(timeout=2)

class ChildJob:
    def __init__(self):
        self.handle=None
        if os.name!='nt':return
        class BASIC(ctypes.Structure):
            _fields_=[('PerProcessUserTimeLimit',ctypes.c_longlong),('PerJobUserTimeLimit',ctypes.c_longlong),
                ('LimitFlags',w.DWORD),('MinimumWorkingSetSize',ctypes.c_size_t),('MaximumWorkingSetSize',ctypes.c_size_t),
                ('ActiveProcessLimit',w.DWORD),('Affinity',ctypes.c_size_t),('PriorityClass',w.DWORD),('SchedulingClass',w.DWORD)]
        class IO(ctypes.Structure):
            _fields_=[(name,ctypes.c_ulonglong) for name in ['ReadOperationCount','WriteOperationCount','OtherOperationCount','ReadTransferCount','WriteTransferCount','OtherTransferCount']]
        class EXTENDED(ctypes.Structure):
            _fields_=[('BasicLimitInformation',BASIC),('IoInfo',IO),('ProcessMemoryLimit',ctypes.c_size_t),
                ('JobMemoryLimit',ctypes.c_size_t),('PeakProcessMemoryUsed',ctypes.c_size_t),('PeakJobMemoryUsed',ctypes.c_size_t)]
        k=ctypes.WinDLL('kernel32',use_last_error=True);self.k=k
        k.CreateJobObjectW.argtypes=[ctypes.c_void_p,w.LPCWSTR];k.CreateJobObjectW.restype=w.HANDLE
        k.SetInformationJobObject.argtypes=[w.HANDLE,ctypes.c_int,ctypes.c_void_p,w.DWORD]
        k.AssignProcessToJobObject.argtypes=[w.HANDLE,w.HANDLE];k.CloseHandle.argtypes=[w.HANDLE]
        self.handle=k.CreateJobObjectW(None,None)
        info=EXTENDED();info.BasicLimitInformation.LimitFlags=0x2000 | 0x200
        info.JobMemoryLimit=512*1024*1024
        if not self.handle or not k.SetInformationJobObject(self.handle,9,ctypes.byref(info),ctypes.sizeof(info)):
            self.close();raise GateError('child_job_setup_failed')
    def assign(self, process):
        if self.handle and not self.k.AssignProcessToJobObject(self.handle,w.HANDLE(int(process._handle))):
            process.kill();process.wait(timeout=10);raise GateError('child_job_assignment_failed')
    def close(self):
        if self.handle:self.k.CloseHandle(self.handle);self.handle=None
    def __enter__(self):return self
    def __exit__(self,*a):self.close()
