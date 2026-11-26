#!/usr/bin/env python3
"""Read-only comparison and exact ID disposition; no legality validator or image reads."""
import collections, hashlib, json, os, sys, zipfile
from pathlib import Path
REG='cf4df343979e930a47e3a71e083a3943e013895f'
NAMES='4b6f028a7cd29b3276f6ab5af84845bf034ea3ab'
TYPES='bfeba203f6cd0d891d56ae60a5ec4f761209cb6b'
BUNDLE='36cf09da11f2b335d6c1181799c751dc06039b8f038392c11d4fd49377a664ef'
def need(x):
    if not x:raise ValueError('contract')
def blob(b):return hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()
def read(p,limit=32*1024*1024):
    need(p.is_file() and not p.is_symlink() and p.stat().st_size<=limit);return p.read_bytes()
def unique(pairs):
    d={}
    for k,v in pairs:need(k not in d);d[k]=v
    return d
def decode(b):return json.loads(b,object_pairs_hook=unique,parse_constant=lambda x: (_ for _ in ()).throw(ValueError('nonfinite')))
def canon(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False)
def save(p,x):
    with p.open('x') as f:json.dump(x,f,indent=2,sort_keys=True,ensure_ascii=True);f.write('\n')
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
def compare(old,new):
    need(isinstance(old,dict) and isinstance(new,dict))
    result={'canonical_json_equal':canon(old)==canon(new),'keys_only_old':len(old.keys()-new.keys()),'keys_only_fixed':len(new.keys()-old.keys()),'changed_keys':[],'list_fields':{}}
    for k in sorted(old.keys()&new.keys()):
        a,b=old[k],new[k]
        if canon(a)!=canon(b):result['changed_keys'].append(k if k in ('regulation','rule','season','specPatch','specialElements','updated','species','items','moves') else '[other]')
        if k in ('species','items','moves') and isinstance(a,list) and isinstance(b,list):
            ac=collections.Counter(map(canon,a));bc=collections.Counter(map(canon,b))
            result['list_fields'][k]={'old_count':len(a),'fixed_count':len(b),'only_old_count':sum((ac-bc).values()),'only_fixed_count':sum((bc-ac).values()),'same_multiset':ac==bc,'same_order':canon(a)==canon(b)}
    return result

def mapping(ids,names,types,reg):
    by=collections.defaultdict(list)
    for x in names['species']:by[x['id']].append(x['en'])
    legal=set(reg['species']);need(len(legal)==len(reg['species']))
    def battle_only(en):return en.endswith(('-Mega','-Mega-X','-Mega-Y','-Mega-Z')) or en in ('Greninja-Bond','Palafin-Hero','Mimikyu-Busted','Morpeko-Hangry')
    rows=[];matched=set()
    for i in ids:
        a=by[i];en=a[0] if len(a)==1 else None
        status='unknown_id' if not a else 'ambiguous_id' if len(a)!=1 else 'battle_only_excluded' if battle_only(en) else 'outside_fixed_dictionary' if en not in legal or en not in types else 'exact_dictionary_candidate'
        if status=='exact_dictionary_candidate':matched.add(en)
        rows.append({'reference_id':i,'exact_name':en,'disposition':status})
    target={x for x in legal if not battle_only(x)}
    return rows,{'counts':dict(collections.Counter(x['disposition'] for x in rows)),'reference_ids':len(rows),'mapped_distinct_names':len(matched),'fixed_dictionary_nonbattle_only_count':len(target),'dictionary_names_without_exact_mapping':len(target-matched),'registration_legality_measured':False,'aliases_inferred':False}

def locate_restore(home):
    roots=[]
    for d in (home/'champions-backups').glob('pre-f-restore-*'):
        p=d/'anonymous-isolated-restore-result.json'
        if not p.is_file():continue
        j=decode(read(p));r=d/'restored'
        if j.get('schema')!='pre-f-isolated-restore-v1' or j.get('archive_sha256_verified') is not True or j.get('regular_files_verified')!=991 or j.get('all_regular_files_verified') is not True or not r.is_dir():continue
        for x in r.iterdir():
            if x.is_dir() and not x.is_symlink() and all((x/'data'/n).is_file() for n in ('regulation.json','names_index.json','species_types.json')):roots.append(x)
    need(roots)
    signatures={tuple(blob(read(x/'data'/n)) for n in ('regulation.json','names_index.json','species_types.json')) for x in roots}
    need(len(signatures)==1);return roots[0]

def run(fixed,home,out):
    b=read(fixed);need(blob(b)==REG);reg=decode(b);r=locate_restore(home)
    old=read(r/'data/regulation.json');n=read(r/'data/names_index.json');t=read(r/'data/species_types.json')
    need(blob(n)==NAMES and blob(t)==TYPES)
    result={'fixed_reg_blob_verified':True,'restored_reg_blob':blob(old),'byte_equal':old==b,'difference':compare(decode(old),reg),'mapping_status':'blocked_bundle_not_found'}
    dirs=[home,home/'Downloads',home/'Desktop',home/'Documents',home/'champions-vision-research',home/'workspace/preview_images_export']
    found=[p for d in dirs if d.is_dir() for p in d.glob('PV16-F-R4*.zip') if p.is_file() and not p.is_symlink() and p.stat().st_size<=128*1024*1024 and sha(p)==BUNDLE]
    if not found:return result
    with zipfile.ZipFile(found[0]) as z:
        def member(k,size):need(z.getinfo(k).file_size<=size);return z.read(k)
        h=decode(member('members-sha256.json',1024*1024));raw=member('features-full.json',32*1024*1024);need(hashlib.sha256(raw).hexdigest()==h['features-full.json']);refs=decode(raw)['references'];ids=sorted({x['id'] for x in refs});need(len(ids)==293 and len(refs)==712)
    rows,summary=mapping(ids,decode(n),decode(t),reg)
    save(out/'PRIVATE-293-id-crosswalk-v2.json',{'schema':'fi-293-dictionary-crosswalk-v2','rows':rows,'summary':summary})
    result.update(mapping_status='exact_dictionary_disposition_complete',verified_bundle=True,features_member_verified=True,mapping=summary,private_crosswalk_written=True)
    return result
if __name__=='__main__':
    os.umask(0o077);out=Path(sys.argv[2]).resolve();need(out.is_dir() and out.name.startswith('fi-r2-r3-limited-'))
    try:r=run(Path(sys.argv[1]),Path.home(),out)
    except Exception as e:r={'status':'blocked_or_failed','error_type':type(e).__name__}
    save(out/'anonymous-r2-dictionary-v2.json',r)
    print(json.dumps(r,indent=2))
