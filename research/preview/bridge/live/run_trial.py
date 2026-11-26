"""Run a bounded isolated trial, sample only its own process group, print aggregates."""
import json, math, os, signal, subprocess, time, re, sys
from pathlib import Path
from collections import Counter


def quantile(xs,p):
    if not xs:return None
    a=sorted(xs);i=(len(a)-1)*p;j=int(i)
    return round(a[j]+(a[min(j+1,len(a)-1)]-a[j])*(i-j),3)


def timing(xs):
    return {'n':len(xs),'median':quantile(xs,.5),'p95':quantile(xs,.95),'max':quantile(xs,1)}


def species_id(s):
    return re.sub('[^a-z0-9]','',s.lower()) if isinstance(s,str) else ''


def summarize(v):
    assert v['schema']=='pv16-live-trial-v1' and v['accepted'] is False
    rows=v['frames'];assert len(rows)<=100 and [r['frame'] for r in rows]==list(range(1,len(rows)+1))
    status=Counter(r['new_status'] for r in rows);cross=Counter();routes=Counter()
    shared=agree=old_slots=new_slots=both_six=complete_agree=0
    new_ms=[];old_gate_ms=[];old_rank_ms=[];age=[]
    valid={'ranked','held','error','bridge_failure','integrity_failure','busy','disabled','submitted'}
    for r in rows:
        assert r['accepted'] is False and r['new_status'] in valid
        old_gate_ms.append(r['legacy_gate_ms']);age.append(r['snapshot_age_ms'])
        old=r['legacy_names'];gate=r['legacy_gate']
        if gate:old_rank_ms.append(r['legacy_rank_ms'])
        old_slots+=sum(isinstance(s,str) and bool(s) for s in old)
        q=r.get('new_result');new=[]
        if q is not None:
            assert q['accepted'] is False and q['scene_authenticated'] is False and q['frame_sha256']==r['frame_sha256'] and q['status']==r['new_status']
            assert len(q['slots'])==6
            new=[s[0][0] if s else None for s in q['slots']]
            new_slots+=sum(x is not None for x in new)
            if q['route']:routes[q['route']]+=1
            cross[('old_gate' if gate else 'old_no_gate')+'__'+r['new_status']]+=1
        if 'new_exchange_ms' in r:new_ms.append(r['new_exchange_ms'])
        if len(old)==6 and len(new)==6:
            comparisons=[species_id(a)==species_id(b) for a,b in zip(old,new) if species_id(a) and species_id(b)]
            shared+=len(comparisons);agree+=sum(comparisons)
            if len(comparisons)==6:both_six+=1;complete_agree+=all(comparisons)
    submitted=sum(status[k] for k in ('ranked','held','error','bridge_failure','integrity_failure','submitted'))
    fault=sum(status[k] for k in ('error','bridge_failure','integrity_failure','disabled','submitted'))
    old_positive=sum(bool(r['legacy_gate']) for r in rows)
    out={'scope':v['scope'],'frames':len(rows),'polls':v['polls'],'old_gate_positive':old_positive,
         'new_status':dict(status),'cross_gate':dict(cross),'routes':dict(routes),'submitted':submitted,
         'old_candidate_slots':old_slots,'new_candidate_slots':new_slots,'comparable_nonempty_slots':shared,
         'normalized_id_agreement':agree,'both_six_nonempty_frames':both_six,'all_six_id_agreement_frames':complete_agree,
         'warmup_ms':round(v['warmup_ms'],3),'sampling_elapsed_ms':round(v['sampling_elapsed_ms'],3),
         'snapshot_age_ms':timing(age),'legacy_gate_ms':timing(old_gate_ms),'legacy_rank_ms':timing(old_rank_ms),
         'new_exchange_ms':timing(new_ms),'worker_cleaned':v['worker_cleaned'],'state_paths_absent':v['state_paths_absent']}
    out['limited_transport_pass']=bool(rows and not fault and submitted and v['worker_cleaned'] and v['state_paths_absent'])
    out['mixed_scene_evidence']=bool(old_positive and old_positive<len(rows) and status['ranked'] and status['held'])
    out['independent_accuracy_measured']=False
    return out


def process_rows():
    text=subprocess.check_output(['ps','-axo','pid=,ppid=,pcpu=,rss='],text=True,timeout=2)
    rows={}
    for line in text.splitlines():
        a=line.split()
        if len(a)!=4:continue
        try:rows[int(a[0])]=(int(a[1]),float(a[2]),int(a[3])/1024)
        except ValueError:pass
    return rows


def descendants(rows,pid):
    tree={pid}
    while True:
        bigger=tree|{p for p,x in rows.items() if x[0] in tree}
        if bigger==tree:return tree
        tree=bigger


def run():
    root=Path.cwd();assert root.name.startswith('pv16-live-trial.') and root.stat().st_mode&0o077==0
    assert not (root/'private-pairs.json').exists()
    p=subprocess.Popen([str(root/'reader-live-trial'),'--read-only-live-trial','90','60'],start_new_session=True)
    cpu=[];rss=[];child_cpu=[];child_rss=[];observed=set();errors=0
    deadline=time.monotonic()+140;timedout=False;forced=False;interrupted=False
    try:
        while p.poll() is None:
            if time.monotonic()>deadline:timedout=True;break
            try:
                rows=process_rows();tree=descendants(rows,p.pid)
                kids=tree-{p.pid};observed.update(kids)
                active=[rows[k] for k in tree if k in rows];child=[rows[k] for k in kids if k in rows]
                if active:cpu.append(sum(x[1] for x in active));rss.append(sum(x[2] for x in active))
                if child:child_cpu.append(sum(x[1] for x in child));child_rss.append(sum(x[2] for x in child))
            except (OSError,subprocess.SubprocessError):errors+=1
            time.sleep(.5)
    except KeyboardInterrupt:interrupted=True
    finally:
        # Never signal an arbitrary group: Foundation Process may use another pgid.
        # On timeout/interrupt signal only currently observed descendants of our living
        # trial, then the Popen-owned trial. Do not kill an unverified reparented PID.
        if p.poll() is None:
            forced=True
            try:
                rows=process_rows();kids=descendants(rows,p.pid)-{p.pid};observed.update(kids)
                for k in kids:
                    if p.poll() is None and k in descendants(process_rows(),p.pid)-{p.pid}:
                        try:os.kill(k,signal.SIGTERM)
                        except ProcessLookupError:pass
            except (OSError,subprocess.SubprocessError):errors+=1
            if p.poll() is None:p.terminate()
            try:p.wait(timeout=3)
            except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
        else:p.wait()
    # On abnormal shutdown, wait for observed worker PID(s) to disappear. This is
    # conservative diagnostic evidence, not identity proof (PID reuse is possible).
    residual=None
    try:
        end=time.monotonic()+3
        while True:
            residual=len(observed&set(process_rows()))
            if not residual or time.monotonic()>=end:break
            time.sleep(.1)
    except (OSError,subprocess.SubprocessError):errors+=1
    out={'exit_code':p.returncode,'watchdog_timeout':timedout,'interrupted':interrupted,'forced_trial_cleanup':forced,
         'observed_child_count':len(observed),'observed_child_pids_still_present':residual,'resource_sample_errors':errors,
         'trial_tree_cpu_percent_ps':timing(cpu),'trial_tree_rss_MiB_ps':timing(rss),
         'child_cpu_percent_ps':timing(child_cpu),'child_rss_MiB_ps':timing(child_rss)}
    f=root/'private-pairs.json'
    if f.exists():out.update(summarize(json.loads(f.read_text())))
    else:out['limited_transport_pass']=False
    if p.returncode!=0 or timedout or forced or interrupted or residual!=0:out['limited_transport_pass']=False
    (root/'aggregate.json').write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')
    print('LIVE_TRIAL_AGGREGATE_BEGIN');print(json.dumps(out,indent=2,allow_nan=False));print('LIVE_TRIAL_AGGREGATE_END')
    print('PRIVATE_OUTPUT_LOCAL_ONLY='+str(root))
    return 0 if out['limited_transport_pass'] else 1


if __name__=='__main__':sys.exit(run())
