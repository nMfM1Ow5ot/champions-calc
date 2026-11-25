#!/usr/bin/env python3
"""Offline research acceptance runner; no OCR, installs, or battle-state writes."""
import argparse
import hashlib
import importlib
import json
import re
from pathlib import Path
import champions_ocr_guard_v9 as guard
import champions_ocr_plate_pilot_v10 as plate
import champions_ocr_message_pilot_v11 as message
import champions_ocr_evidence_v7 as evidence
import champions_ocr_association_v8 as assoc

MODULES = ('replay_v6','evidence_v7','association_v8','guard_v9','plate_pilot_v10','message_pilot_v11')
# Observed-query neighborhoods checked against pinned dictionary; NOT full lexicon.
SPECIES = ('ガオガエン','フラエッテ','リザードン','リザード','フシギバナ','ゴリランダー')
MOVES = ('ねっぷう','ねっとう','ウェザーボール','げんしのちから','しんぴのちから','まもる')
STONES = ('リザードナイトY',)


def regression():
    out = {}
    for mod in MODULES:
        m = importlib.import_module('champions_ocr_'+mod)
        r = m.self_test()
        checks = {x['name']:x['pass'] for x in r['checks']} if 'checks' in r else r
        out[mod] = {'pass':sum(v is True for v in checks.values()),'total':len(checks),'failed':[k for k,v in checks.items() if v is not True]}
    return out


def analyze(report, species, moves, stones):
    guard.replay(report,species,moves)  # validate normalized boxes against originals
    frames = {f['case']:f for f in report['frames']}
    if not all(x['status']=='EXECUTED_UNSCORED' for x in report['results']):
        raise ValueError('unexecuted/failed pass; incomplete dataset')
    records = {}
    for r in report['results']:
        if r['method']!='full_frame': continue
        case=r['case']; f=frames[case]
        if case in records: raise ValueError('duplicate primary pass')
        b=r['boxes_original_normalized']
        p=plate.inspect(b,species); m=message.inspect(b,species,stones)
        entry={'image_sha256':f['sha256'],'plate':p,'message':m,'command':None}
        if p['screen_candidate']=='MOVE_MENU':
            old=evidence.analyze(b,species,moves,'full_frame')
            entry['command']=assoc.command(b,old['move_candidates'],species)
        records[case]=entry
    if set(records)!=set(frames): raise ValueError('primary pass coverage mismatch')
    return records


def aggregate(records):
    hp=messages=moves=pairs=0; screens={}
    for v in records.values():
        p=v['plate']; m=v['message']; c=v['command']
        if p['event_emission']!='DISABLED' or m['event_emission']!='DISABLED':raise ValueError('unsafe emission')
        hp+=len(p['hp_candidates']); messages+=int(m['candidate'] is not None)
        k=p['screen_candidate'];screens[k]=screens.get(k,0)+1
        if c:
            moves+=sum(len(x['names']) for x in c['moves']);pairs+=sum(len(x['pairs']) for x in c['pp'])
    return {'frames':len(records),'hp_candidates':hp,'message_candidates':messages,'move_name_candidates':moves,'complete_pp_candidates':pairs,'screens':screens,'confirmed_events':0}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',nargs=2,action='append',metavar=('PATH','SHA256'),default=[])
    p.add_argument('--dictionary',type=Path);p.add_argument('--dictionary-sha256');p.add_argument('--out',type=Path)
    a=p.parse_args();species,moves=SPECIES,MOVES; scope='observed_query_neighborhood_fixture'
    if a.dictionary:
        raw=a.dictionary.read_bytes()
        if hashlib.sha256(raw).hexdigest()!=a.dictionary_sha256:raise ValueError('dictionary SHA mismatch')
        d=json.loads(raw);species=tuple(d['species'].values());moves=tuple(d['moves'].values());scope='supplied_hash_verified_dictionary'
    tests=regression();reports=[];seen=set()
    for path,digest in a.archive:
        if not re.fullmatch('[0-9a-f]{64}',digest) or digest in seen:raise ValueError('invalid or duplicate archive hash')
        seen.add(digest);r=guard.load_archive(Path(path),digest)
        records=analyze(r,species,moves,STONES)
        reports.append({'archive_sha256':digest,'ocr_passes':len(r['results']),**aggregate(records)})
    result={'schema':'ocr-acceptance-v12','dictionary_scope':scope,'stone_scope':'single observed label','regression':tests,'archives':reports,'independent_battle_validation':'NOT_ESTABLISHED','production_acceptance':'NOT_GRANTED'}
    s=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
    if a.out:
        with a.out.open('x',encoding='utf8') as f:f.write(s)
    print(s,end='');return int(any(x['failed'] for x in tests.values()))

if __name__=='__main__':raise SystemExit(main())
