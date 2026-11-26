#!/usr/bin/env python3
"""R2 Mac read-only inventory + R3 frozen fixture replay; no production startup."""
import ast, collections, hashlib, json, os, pathlib, platform, re, shutil, signal, subprocess, sys, tempfile, zipfile
from pathlib import Path
os.umask(0o077)
ROOT=Path.home()
B=ROOT/'champions-backups'
STUB_SHA='1875cb0c7475c876fdc6cde878e267dd85a1fe01'
MAIN='8fe118aefba0867979cbf49a14d068fc8bf37205'
ASSET='36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef'
ARCHIVE='570237e0ff335477eed827205a6938507295772d548a4e33ffaeec380c46c8f7'
EXPECTED={'reader.swift':'038267041215f0f47e76156acf32ea7d0977a9fd','start_all.sh':'cd1c5e24bb3d973018b2923286103dd33dcc50f8','serve.py':'4ed10cf3a628a5fb64a5ec8f351a9d6abae18b30','data/names_index.json':'4b6f028a7cd29b3276f6ab5af84845bf034ea3ab','data/species_types.json':'bfeba203f6cd0d891d56ae60a5ec4f761209cb6b','data/regulation.json':'cf4df343979e930a47e3a71e083a3943e013895f'}
def gitblob(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def need(x):
    if not x:raise ValueError('contract')
def safe(p,limit=32*1024*1024):
    need(p.is_file() and not p.is_symlink() and p.stat().st_size<=limit)
    return p.read_bytes()
def readj(p):return json.loads(safe(p))
def local(p):return p.is_file() and not p.is_symlink()
def section(report,key,fn):
    try:report[key]=fn()
    except Exception as e:report[key]={'status':'blocked','error_type':type(e).__name__}

def backup():
    found=[]
    for p in sorted(B.glob('pre-f-restore-*')):
        f=p/'anonymous-isolated-restore-result.json'
        if not local(f):continue
        j=readj(f)
        if not (j.get('schema')=='pre-f-isolated-restore-v1' and j.get('archive_sha256_verified') is True and j.get('regular_files_verified')==991 and j.get('all_regular_files_verified') is True and j.get('all_core_syntax_pass') is True):continue
        for r in (p/'restored').iterdir():
            if r.is_dir() and not r.is_symlink() and all(local(r/n) for n in ('start_all.sh','reader.swift','serve.py','sync_ui.py')):found.append(r)
    need(found)
    signatures={tuple(gitblob(safe(r/n)) for n in ('start_all.sh','reader.swift','serve.py','sync_ui.py')) for r in found}
    need(len(signatures)==1)
    return found[0]

def inventory(r):
    s=safe(r/'sync_ui.py')
    tree=ast.parse(s)
    def callname(n):
        if isinstance(n,ast.Name):return n.id
        if isinstance(n,ast.Attribute):return callname(n.value)+'.'+n.attr
        return '?'
    calls=collections.Counter(callname(n.func) for n in ast.walk(tree) if isinstance(n,ast.Call))
    # Indicators only, not a proof of behavior. Do not emit source, literals or paths.
    flags={
        'network_calls':any(re.search(r'(urlopen|urlretrieve|requests\.|httpx\.|http\.client|socket\.)',k) for k in calls),
        'subprocess_calls':any(re.search(r'(subprocess\.|os\.system|os\.exec|os\.spawn)',k) for k in calls),
        'replace_calls':any(k.endswith(('.replace','.rename')) for k in calls),
        'hash_calls':any(re.search(r'(sha256|hashlib)',k) for k in calls),
        'file_writes_possible':any(k.endswith(('.write','.write_text','.write_bytes','.unlink','.remove','.replace','.rename','.mkdir')) or k=='open' for k in calls),
        'manifest_reference':b'ui_manifest.json' in s,
        'force_flag_reference':b'--force' in s,
        'raw_github_reference':b'raw.githubusercontent.com' in s,
        'main_reference':b'/main/' in s or b'ref=main' in s,
        'restart_reference':bool(re.search(rb'\brestart\b|exit\(42\)|execv',s,re.I))}
    core={n:(gitblob(safe(r/n))==h if local(r/n) else None) for n,h in EXPECTED.items()}
    # Match current sources by four restored core hashes; mdfind results are local only.
    matches=set()
    try:
        q=subprocess.run(['/usr/bin/mdfind','-0','-onlyin',str(ROOT),'kMDItemFSName == "start_all.sh"'],capture_output=True,timeout=15,check=True)
        target={n:gitblob(safe(r/n)) for n in ('start_all.sh','reader.swift','serve.py','sync_ui.py')}
        for raw in q.stdout.split(b'\0'):
            if not raw:continue
            p=Path(os.fsdecode(raw)).parent.resolve()
            if B==p or B in p.parents:continue
            if all(local(p/n) and gitblob(safe(p/n))==h for n,h in target.items()):matches.add(p)
        source_status='matched' if len(matches)==1 else 'not_unique'
    except Exception:source_status='search_unavailable'
    return {'status':'read_only_static','restored_core_and_data_match_fixed_main':core,'sync_script_git_blob':gitblob(s),'sync_script_ast_parse':True,'sync_indicators_not_behavior_proof':flags,'current_source_status':source_status,'current_source_match_count':len(matches),'sync_script_executed':False}

def host(tmp):
    out={'system':platform.system(),'architecture':platform.machine(),'macos':platform.mac_ver()[0],'python':platform.python_version(),'python_architecture':platform.machine()}
    try:
        q=subprocess.run(['/usr/bin/swiftc','--version'],capture_output=True,text=True,timeout=15,check=True)
        m=re.search(r'Swift version ([0-9.]+)',q.stdout);out['swift_version']=m.group(1) if m else None
    except Exception:out['swift_version']=None
    py=ROOT/'champions-vision-research/.venv/bin/python'
    if not py.is_file():out['vision_venv']={'status':'missing'};return out
    cmd="import json,platform,sys,importlib.metadata as m; print(json.dumps({'python':platform.python_version(),'architecture':platform.machine(),'packages':{k: next((d.version for d in m.distributions() if d.metadata.get('Name','').lower()==k),None) for k in ['numpy','opencv-python','opencv-python-headless','opencv-contrib-python']}}))"
    # Metadata only: no cv2/numpy import or startup of production app.
    env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','HOME':str(tmp),'TMPDIR':str(tmp),'PYTHONDONTWRITEBYTECODE':'1','PYTHONNOUSERSITE':'1'}
    try:
        q=subprocess.run([str(py),'-I','-B','-c',cmd],env=env,cwd=tmp,capture_output=True,text=True,timeout=15,check=True)
        out['vision_venv']={'status':'metadata_only',**json.loads(q.stdout)}
    except Exception:out['vision_venv']={'status':'metadata_unavailable'}
    return out

def showdown():
    roots=[ROOT/'showdown-virtual-env',ROOT/'workspace/showdown-virtual-env',ROOT/'workspace/virtual_envs/showdown-virtual-env']
    out=[]
    for p in roots:
        if not (p/'.git').exists():continue
        env=dict(os.environ,GIT_OPTIONAL_LOCKS='0',GIT_TERMINAL_PROMPT='0')
        g=subprocess.run(['git','-C',str(p),'rev-parse','HEAD'],capture_output=True,text=True,check=True,timeout=10,env=env).stdout.strip()
        need(re.fullmatch('[0-9a-f]{40}',g))
        f=p/'config/formats.ts'
        out.append({'head':g,'matches_inspected_revision':g=='29f2d9969159fd23f8bb96e177a70072fe573b0e','format_source_matches_inspected_blob':local(f) and gitblob(safe(f))=='262ad7b531ff8191f73f2f3159af0c3e51f06ecf','built_sim_present':(p/'dist/sim').is_dir(),'validator_executed':False})
    return {'status':'local_candidates' if out else 'not_found_in_known_paths','candidates':out,'registration_legality_measured':False}

def assets(r):
    dirs=[ROOT,ROOT/'Downloads',ROOT/'Desktop',ROOT/'Documents',ROOT/'champions-vision-research',ROOT/'workspace/preview_images_export']
    # Only known directories; no recursive disk scan; verify exact F bundle before reading member.
    candidates=[]
    for d in dirs:
        if not d.is_dir():continue
        for p in d.glob('PV16-F-R4*.zip'):
            if local(p) and p.stat().st_size<=128*1024*1024:candidates.append(p)
    found=[]
    for p in candidates:
        if sha(p)==ASSET:found.append(p)
    o={'verified_bundle_found':bool(found),'bundle_candidate_count':len(candidates),'image_archive_identity_expected':ARCHIVE,'image_archive_present_by_name_only':any(local(p) for d in dirs if d.is_dir() for p in d.glob('preview_images_all*.zip')),'image_archive_opened':False,'ongoing_use_rights':'not_confirmed','calibration':'unavailable'}
    cal=ROOT/'champions-vision-research/pv16-pv11-hybrid-validation.tTb2IN/private-calibration.npy'
    cr=cal.parent/'anonymous-pv11-hybrid-validation-v1.json'
    if local(cal) and local(cr):
        j=readj(cr)
        if j.get('schema')=='pv16-pv11-hybrid-validation-v1' and j.get('regression_pass') is True and j.get('frozen_calibration_local_only') is True and cal.stat().st_size<100000:
            o['calibration']='prior_successful_local_record_found'
            o['calibration_sha256']=sha(cal)
            o['calibration_provenance_independently_verified']=False
    if not found:return o
    with zipfile.ZipFile(found[0]) as z:
        def member(n,limit):
            need(z.getinfo(n).file_size<=limit)
            return z.read(n)
        hashes=json.loads(member('members-sha256.json',1024*1024))
        raw=member('features-full.json',32*1024*1024)
        need(hashlib.sha256(raw).hexdigest()==hashes.get('features-full.json'))
        rows=json.loads(raw)['references'];ids=sorted({x['id'] for x in rows})
        need(len(ids)==293 and len(rows)==712)
    o.update(reference_ids=len(ids),reference_rows=len(rows),features_member_verified=True)
    ds={}
    for n in ('data/names_index.json','data/species_types.json','data/regulation.json'):
        p=r/n
        if not local(p) or gitblob(safe(p))!=EXPECTED[n]:
            o['mapping_status']='blocked_fixed_dictionaries_not_matching';return o
        ds[n]=readj(p)
    names=ds['data/names_index.json']['species'];by=collections.defaultdict(list)
    for n in names:by[n['id']].append(n['en'])
    legal=set(ds['data/regulation.json']['species']);types=ds['data/species_types.json']
    def battle_only(en):return en.endswith(('-Mega','-Mega-X','-Mega-Y','-Mega-Z')) or en in ('Greninja-Bond','Palafin-Hero','Mimikyu-Busted','Morpeko-Hangry')
    counts=collections.Counter();mapped=set()
    for i in ids:
        x=by[i]
        if not x:counts['unknown_id']+=1
        elif len(x)!=1:counts['ambiguous_id']+=1
        elif battle_only(x[0]):counts['battle_only_excluded']+=1
        elif x[0] not in legal or x[0] not in types:counts['outside_fixed_dictionary']+=1
        else:counts['exact_dictionary_candidate']+=1;mapped.add(x[0])
    target={x for x in legal if not battle_only(x)}
    o.update(mapping_status='exact_dictionary_only',mapping_counts=dict(counts),fixed_dictionary_nonbattle_only_count=len(target),mapped_distinct_names=len(mapped),dictionary_names_without_exact_mapping=len(target-mapped),registration_legality_measured=False,aliases_inferred=False)
    return o

def run_stub(stub,tmp):
    need(gitblob(safe(stub))==STUB_SHA)
    # New session/process group, independent from production. Only this group may be signalled.
    env={'PATH':'/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin','HOME':str(tmp),'TMPDIR':str(tmp),'PYTHONDONTWRITEBYTECODE':'1','PYTHONNOUSERSITE':'1'}
    p=subprocess.Popen([sys.executable,'-I','-B',str(stub)],cwd=tmp,env=env,start_new_session=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        stdout,stderr=p.communicate(timeout=145)
    except subprocess.TimeoutExpired:
        # Child harness has an internal 90s compiler and 8s/case cap.
        # Kill only our isolated process group while its leader is still owned.
        if p.poll() is None:
            try:os.killpg(p.pid,signal.SIGKILL)
            except ProcessLookupError:pass
        try:p.communicate(timeout=5)
        except subprocess.TimeoutExpired:pass
        return {'status':'outer_timeout','full_process_tree_cleanup_proven':False}
    try:
        j=json.loads(stdout)
        need(j.get('schema')=='fi-r3-ipc-stub-v0.1' and j.get('total')==17 and len(j['tests'])==17)
        modes={'normal','stderr_flood','ready_wrong','ready_hang','write_stall','crash','hang','stop','partial_header','oversize','partial_body','duplicate','invalid_utf8','wrong_frame','wrong_worker','wrong_digest','error'}
        need({r['mode'] for r in j['tests']}==modes)
        tests=[{k:r[k] for k in ('mode','status','expected','passed','reaped','kill_escalated','elapsed_ms')} for r in j['tests']]
        return {'status':'completed','platform':j['platform'],'python':j['python'],'swift_version':re.search(r'Swift version ([0-9.]+)',j['swift']).group(1),'returncode':p.returncode,'passed':sum(r['passed'] is True for r in tests),'total':17,'all_reaped':all(r['reaped'] is True for r in tests),'tests':tests,'full_process_tree_cleanup_proven':False}
    except Exception:return {'status':'failed_or_incomplete','returncode':p.returncode,'stderr_present':bool(stderr),'full_process_tree_cleanup_proven':False}

def main():
    need(platform.system()=='Darwin')
    stub=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve()
    need(out.parent.name.startswith('fi-r2-r3-mac-') and out.name=='anonymous-fi-r2-r3-mac-v1.json')
    report={'schema':'fi-r2-r3-mac-v1','production_started':False,'production_modified_by_script':False,'live_capture_performed':False,'sync_executed':False,'private_images_exported':False,'asset_rights_confirmed':False,'actual_capture_profile_measured':False}
    with tempfile.TemporaryDirectory(prefix='fi-r2-r3-tmp-',dir=out.parent) as t:
        tmp=Path(t)
        section(report,'host',lambda:host(tmp))
        try:r=backup()
        except Exception:r=None
        if r:
            section(report,'backup_static_inventory',lambda:inventory(r))
            section(report,'assets_and_mapping',lambda:assets(r))
        else:report['backup_static_inventory']={'status':'verified_restore_not_unique_or_missing'};report['assets_and_mapping']={'status':'blocked_restore_unavailable'}
        section(report,'showdown',showdown)
        section(report,'ipc',lambda:run_stub(stub,tmp))
    out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'report_schema':report['schema'],'ipc':{k:v for k,v in report.get('ipc',{}).items() if k in ('status','passed','total','all_reaped')},'inventory_status':report.get('backup_static_inventory',{}).get('status'),'mapping_status':report.get('assets_and_mapping',{}).get('mapping_status')},indent=2))
if __name__=='__main__':main()
