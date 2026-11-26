#!/usr/bin/env python3
import ast, hashlib, sys
from pathlib import Path
b=Path(sys.argv[1]).read_bytes()
assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()=='1875cb0c7475c876fdc6cde878e267dd85a1fe01'
s=b.decode('utf-8')
def rep(a,c):
    global s
    if s.count(a)!=1:raise ValueError('patch context mismatch')
    s=s.replace(a,c)
rep("        if mode=='stop': os.kill(os.getpid(),signal.SIGSTOP);return", "        if mode=='stop': os.kill(os.getpid(),signal.SIGSTOP);return\n        if mode=='ignore_term':\n            signal.signal(signal.SIGTERM,signal.SIG_IGN);time.sleep(30);return")
rep('let a=CommandLine.arguments', '''func stopped(_ p:Process)->Bool {
    guard p.isRunning else {return false}
    let q=Process();let pipe=Pipe();q.executableURL=URL(fileURLWithPath:"/bin/ps")
    q.arguments=["-o","stat=","-p",String(p.processIdentifier)]
    q.standardOutput=pipe;q.standardError=FileHandle.nullDevice
    do {try q.run();try pipe.fileHandleForWriting.close();q.waitUntilExit()
        let data=pipe.fileHandleForReading.readDataToEndOfFile()
        return q.terminationStatus==0 && (String(data:data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("T") ?? false)
    } catch {return false}
}
let a=CommandLine.arguments''')
rep('var status="ok";var reaped=false;var escalated=false','var status="ok";var reaped=false;var escalated=false;var launched=false;var stopObserved=false;var termSent=false;var killSent=false;var exitCode:Int32?=nil;var exitReason="unavailable"')
rep('do {try p.run();try input.fileHandleForReading.close();','do {try p.run();launched=true;try input.fileHandleForReading.close();')
rep('try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()\nif p.isRunning && !waitExit(p,80){p.terminate();if !waitExit(p,100){escalated=true;kill(p.processIdentifier,SIGKILL);_ = waitExit(p,500)}}\nif !p.isRunning {p.waitUntilExit();reaped=true}', '''if launched && mode=="stop" {stopObserved=stopped(p)}
try? input.fileHandleForWriting.close();try? output.fileHandleForReading.close()
if launched && p.isRunning && !waitExit(p,80){
    termSent=kill(p.processIdentifier,SIGTERM)==0
    if !waitExit(p,100){escalated=true;killSent=kill(p.processIdentifier,SIGKILL)==0;_ = waitExit(p,500)}
}
if launched && !p.isRunning {p.waitUntilExit();reaped=true;exitCode=p.terminationStatus;exitReason=p.terminationReason == .uncaughtSignal ? "signal" : "exit"}''')
rep('"kill_escalated":escalated,"elapsed_ms"','"kill_escalated":escalated,"stop_observed":stopObserved,"term_sent":termSent,"kill_sent":killSent,"exit_reason":exitReason,"exit_status":exitCode.map{$0 as Any} ?? NSNull(),"elapsed_ms"')
rep("'stop':'timeout','partial_header'","'stop':'timeout','ignore_term':'timeout','partial_header'")
rep("and (mode!='stop' or r['kill_escalated'])", "and (mode!='stop' or (r['stop_observed'] and r['exit_reason']=='signal' and r['exit_status'] in (signal.SIGTERM,signal.SIGKILL))) and (mode!='ignore_term' or (r['term_sent'] and r['kill_escalated'] and r['kill_sent'] and r['exit_reason']=='signal' and r['exit_status']==signal.SIGKILL))")
rep("schema='fi-r3-ipc-stub-v0.1'","schema='fi-r3-ipc-stub-v0.2'")
ast.parse(s)
with Path(sys.argv[2]).open('x') as f:f.write(s)
