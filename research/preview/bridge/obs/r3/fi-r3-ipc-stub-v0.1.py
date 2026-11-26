#!/usr/bin/env python3
"""Synthetic Swift/Python IPC fixture; no production imports, files, network or real images."""
import base64, hashlib, json, os, pathlib, shutil, signal, struct, subprocess, sys, tempfile, time, zlib
SC='champions-preview-ipc-v1.1'
F='pv16-pv11-hybrid-research-v1'
L='00000000-0000-4000-8000-000000000001'
W='00000000-0000-4000-8000-000000000002'
R='00000000-0000-4000-8000-000000000003'
REL='a'*64; ASSET='b'*64; CAL='c'*64; MAP='d'*64

def canon(x): return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode('ascii')
def chunk(k,b): return struct.pack('>I',len(b))+k+b+struct.pack('>I',zlib.crc32(k+b)&0xffffffff)
PIX=b'\x00\x11\x22\x33'
PNG=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(PIX))+chunk(b'IEND',b'')
DIG=hashlib.sha256(PNG).hexdigest()
C=dict(schema=SC,release_set_id=REL,worker_uuid=W)
READY=dict(C,kind='ready',payload_bytes=0,launch_uuid=L,asset_digest=ASSET,calibration_digest=CAL,mapping_digest=MAP,score_kind='joint25-dynamic-gallery-recovery-v2',status='ready')
def request(i):
    return dict(C,kind='analyze',payload_bytes=len(PNG),launch_uuid=L,capture_generation='0',frame_seq=str(i),request_uuid=R[:-1]+str(i),captured_monotonic_ns=str(i),source_profile_id='replay_mock',frame_sha256=DIG,asset_digest=ASSET,encoding='png',width=1,height=1)
def response(q,kind='result'):
    h={k:v for k,v in q.items() if k not in ('encoding','width','height')};h.update(kind=kind,payload_bytes=0)
    if kind=='error': h['error_code']='analysis_error'
    else: h.update(elapsed_analysis_ms=1,result=dict(schema=F,route='held',reason='pv11_no_unique_layout',status='held',accepted=False,scene_authenticated=False,slots=[None]*6,types=None,recovered=None))
    return h

def unique(pairs):
    d={}
    for k,v in pairs:
        if k in d: raise ValueError('duplicate')
        d[k]=v
    return d

def exact(f,n):
    b=f.read(n)
    if len(b)!=n: raise EOFError()
    return b

def recv():
    f=sys.stdin.buffer;n=struct.unpack('>I',exact(f,4))[0]
    if not 1<=n<=16384: raise ValueError('header length')
    raw=exact(f,n);h=json.loads(raw.decode('ascii'),object_pairs_hook=unique)
    if canon(h)!=raw or type(h['payload_bytes']) is not int or not 0<h['payload_bytes']<=16777216: raise ValueError('header')
    return h,exact(f,h['payload_bytes'])

def send(h,raw=None):
    b=canon(h) if raw is None else raw
    sys.stdout.buffer.write(struct.pack('>I',len(b))+b);sys.stdout.buffer.flush()

def check_png(p):
    if p!=PNG or hashlib.sha256(p).hexdigest()!=DIG: raise ValueError('fixture digest')
    # Actual bounded RGB pixel decompression of the exact generated PNG fixture.
    n=struct.unpack('>I',p[33:37])[0]
    if p[37:41]!=b'IDAT' or zlib.decompress(p[41:41+n])!=PIX: raise ValueError('fixture pixel')

def worker(mode):
    if mode=='ready_hang': time.sleep(30);return
    if mode=='ready_wrong': send(dict(READY,release_set_id='f'*64));return
    send(READY)
    if mode=='write_stall': time.sleep(30);return
    for i in (1,2):
        try: q,p=recv()
        except EOFError: return
        if q!=request(i): raise ValueError('request fixture')
        check_png(p)
        h=response(q)
        if mode=='crash': os._exit(23)
        if mode=='hang': time.sleep(30);return
        if mode=='stop': os.kill(os.getpid(),signal.SIGSTOP);return
        if mode=='partial_header': os.write(1,b'\x00\x00');return
        if mode=='oversize': os.write(1,struct.pack('>I',16385));return
        if mode=='partial_body': os.write(1,struct.pack('>I',20)+b'{}');return
        if mode=='duplicate': send(h,canon(h)[:-1]+b',"kind":"result"}');return
        if mode=='invalid_utf8': send(h,b'\xff');return
        if mode=='wrong_frame': send(dict(h,frame_seq='99'));return
        if mode=='wrong_worker': send(dict(h,worker_uuid=L));return
        if mode=='wrong_digest': send(dict(h,frame_sha256=REL));return
        if mode=='error': send(response(q,'error'));return
        if mode=='stderr_flood': os.write(2,b'x'*131072)
        send(h)

SWIFT=r'''
import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
struct Fault: Error { let kind: String; init(_ k: String){kind=k} }
func now()->UInt64 { DispatchTime.now().uptimeNanoseconds }
func deadline(_ ms:UInt64)->UInt64 { now()+ms*1_000_000 }
func nonblock(_ fd:Int32)throws { let f=fcntl(fd,F_GETFL); if f<0 || fcntl(fd,F_SETFL,f|O_NONBLOCK)<0 {throw Fault("fcntl")} }
func waitFD(_ fd:Int32,_ events:Int16,_ end:UInt64)throws {
    while true {
        let t=now();if t>=end {throw Fault("timeout")}
        var p=pollfd(fd:fd,events:events,revents:0)
        let ms=Int32(min((end-t+999_999)/1_000_000,1000))
        let n=poll(&p,1,ms)
        if n>0 {return};if n==0 {continue};if errno != EINTR {throw Fault("poll")}
    }
}
func readN(_ fd:Int32,_ count:Int,_ end:UInt64)throws->Data {
    var b=[UInt8](repeating:0,count:count);var pos=0
    while pos<count {try waitFD(fd,Int16(POLLIN),end)
        let n=b.withUnsafeMutableBytes { read(fd,$0.baseAddress!.advanced(by:pos),count-pos) }
        if n>0 {pos+=n} else if n==0 {throw Fault("eof")} else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {throw Fault("read")}
    };return Data(b)
}
func writeN(_ fd:Int32,_ data:Data,_ end:UInt64)throws {
    var pos=0
    while pos<data.count {try waitFD(fd,Int16(POLLOUT),end)
        let n=data.withUnsafeBytes { write(fd,$0.baseAddress!.advanced(by:pos),data.count-pos) }
        if n>0 {pos+=n} else if n==0 {throw Fault("write")} else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {throw Fault("write")}
    }
}
func frame(_ h:Data,_ p:Data)->Data { var n=UInt32(h.count).bigEndian;var d=withUnsafeBytes(of:&n){Data($0)};d.append(h);d.append(p);return d }
func recv(_ fd:Int32,_ end:UInt64)throws->Data {
    let b=try readN(fd,4,end);let n=b.reduce(0){$0*256+Int($1)}
    if n<1 || n>16384 {throw Fault("size")};return try readN(fd,n,end)
}
func match(_ data:Data,_ expected:Data)throws {if data != expected {throw Fault("contract")}}
func waitExit(_ p:Process,_ ms:UInt64)->Bool {let end=deadline(ms);while p.isRunning && now()<end {usleep(5000)};return !p.isRunning}
let a=CommandLine.arguments
let mode=a[3]
func bytes(_ i:Int)->Data {Data(base64Encoded:a[i])!}
let p=Process();let input=Pipe();let output=Pipe();p.executableURL=URL(fileURLWithPath:a[1]);p.arguments=[a[2],"--worker",mode];p.standardInput=input;p.standardOutput=output;p.standardError=FileHandle.nullDevice
signal(SIGPIPE,SIG_IGN)
var status="ok";var reaped=false;var escalated=false
let start=now()
do {try p.run();try input.fileHandleForReading.close();try output.fileHandleForWriting.close()
    let w=input.fileHandleForWriting.fileDescriptor,r=output.fileHandleForReading.fileDescriptor
    try nonblock(w);try nonblock(r);try match(recv(r,deadline(1000)),bytes(4))
    if mode=="write_stall" {try writeN(w,Data(repeating:65,count:1_048_576),deadline(250));throw Fault("unexpected")}
    for i in 0..<2 {let end=deadline(250);try writeN(w,frame(bytes(5+i*2),bytes(9)),end);let got=try recv(r,end)
        if mode=="error" {try match(got,bytes(10));throw Fault("worker_error")}
        try match(got,bytes(6+i*2))
    }
} catch let e as Fault {status=e.kind} catch {status="launch_or_io"}
try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
if p.isRunning && !waitExit(p,80){p.terminate();if !waitExit(p,100){escalated=true;kill(p.processIdentifier,SIGKILL);_ = waitExit(p,500)}}
if !p.isRunning {p.waitUntilExit();reaped=true}
let report:[String:Any]=["status":status,"reaped":reaped,"kill_escalated":escalated,"elapsed_ms":Double(now()-start)/1_000_000]
print(String(data:try! JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),encoding:.utf8)!)
'''

def run():
    modes={'normal':'ok','stderr_flood':'ok','ready_wrong':'contract','ready_hang':'timeout','write_stall':'timeout','crash':'eof','hang':'timeout','stop':'timeout','partial_header':'eof','oversize':'size','partial_body':'eof','duplicate':'contract','invalid_utf8':'contract','wrong_frame':'contract','wrong_worker':'contract','wrong_digest':'contract','error':'worker_error'}
    with tempfile.TemporaryDirectory(prefix='fi-r3-ipc-') as d:
        root=pathlib.Path(d);src=root/'stub.swift';src.write_text(SWIFT);exe=root/'stub'
        swift=shutil.which('swiftc');assert swift
        env=dict(os.environ,HOME=d,TMPDIR=d,PYTHONDONTWRITEBYTECODE='1')
        subprocess.run([swift,str(src),'-o',str(exe)],check=True,timeout=90,env=env,cwd=d)
        enc=lambda b:base64.b64encode(b).decode()
        args=[enc(canon(READY)),enc(canon(request(1))),enc(canon(response(request(1)))),enc(canon(request(2))),enc(canon(response(request(2)))),enc(PNG),enc(canon(response(request(1),'error')))]
        results=[]
        for mode,want in modes.items():
            p=subprocess.run([str(exe),sys.executable,str(pathlib.Path(__file__).resolve()),mode,*args],capture_output=True,text=True,timeout=8,env=env,cwd=d)
            r=json.loads(p.stdout);r.update(mode=mode,expected=want,passed=p.returncode==0 and r['status']==want and r['reaped'] and (mode!='stop' or r['kill_escalated']))
            results.append(r)
        return dict(schema='fi-r3-ipc-stub-v0.1',platform=sys.platform,python=sys.version.split()[0],swift=subprocess.check_output([swift,'--version'],text=True).splitlines()[0],tests=results,passed=sum(r['passed'] for r in results),total=len(results))
if __name__=='__main__':
    if len(sys.argv)>1 and sys.argv[1]=='--worker': worker(sys.argv[2])
    else:
        r=run();print(json.dumps(r,indent=2,sort_keys=True));sys.exit(0 if r['passed']==r['total'] else 1)
