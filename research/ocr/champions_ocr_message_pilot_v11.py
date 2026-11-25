#!/usr/bin/env python3
"""Offline message candidate pilot, no confirmed events or state changes."""
import re
import champions_ocr_replay_v6 as v6
import champions_ocr_evidence_v7 as v7
import champions_ocr_association_v8 as v8
import champions_ocr_plate_pilot_v10 as v10

STATS = {'攻撃':'atk','防御':'def','特攻':'spa','特防':'spd','素早さ':'spe','命中率':'acc','回避率':'eva'}
READINGS = {'あいて':'相手','とくこう':'特攻','とくぼう':'特防','こうげき':'攻撃','ぼうぎょ':'防御','すばやさ':'素早さ','はんのう':'反応'}
STAT = '(?:'+'|'.join(STATS)+')'


def text_rows(boxes):
    v8.validate_boxes(boxes)
    ids = [i for i,b in enumerate(boxes) if .19<=v6.center(b)[0]<.625 and .70<=v6.center(b)[1]<.85]
    removed = []
    for i in ids:
        b=boxes[i]; word=READINGS.get(v6.norm(b['text']))
        if not word: continue
        x0,y0,x1,y1=b['xyxy']; h=y1-y0
        if any(j!=i and word in v6.norm(boxes[j]['text']) and h<=.70*v6.height(boxes[j])
               and boxes[j]['xyxy'][0]<x1 and x0<boxes[j]['xyxy'][2]
               and -.018<=boxes[j]['xyxy'][1]-y1<=.025
               and y0<boxes[j]['xyxy'][1] for j in ids):
            removed.append(i)
    kept=[i for i in ids if i not in removed]
    rows=v6.join_rows([boxes[i] for i in kept])
    return {'rows':rows,'body':v6.norm(''.join(rows)),'body_box_ids':kept,'ruby_box_ids':removed}


def parse(body, species, stones):
    def name(raw):
        n=v7.name_evidence(raw,species)
        return n if n['status'] in ('EXACT_TEXT','SUGGESTED') and n['best_distance']<=1 else None
    def event(kind, **kw):return {'kind':kind,**kw,'confirmed':False}
    m=re.fullmatch(r'(.{1,40}?)は(.{1,20}?)と(.{1,20}?)を繰り出した!',body)
    if m:
        a,b=name(m[2]),name(m[3])
        if a and b and a['best_candidates']!=b['best_candidates']:
            return event('SEND_OUT_CANDIDATE',names=[a,b],side=None)
    m=re.fullmatch(r'(相手の)?(.{1,20}?)の('+STAT+r'(?:'+STAT+r')*)が(上がった|下がった|ぐーんと上がった|がくっと下がった)!',body)
    if m:
        n=name(m[2]); stats=re.findall(STAT,m[3])
        if n and len(set(stats))==len(stats):
            return event('STAT_CHANGE_CANDIDATE',name=n,side='opponent' if m[1] else None,stats=[STATS[s] for s in stats],change_text=m[4])
    m=re.fullmatch(r'(相手の)?(.{1,20}?)に効果は(バツグンだ|いまひとつのようだ)!',body)
    if m and (n:=name(m[2])):
        return event('EFFECTIVENESS_CANDIDATE',target=n,side='opponent' if m[1] else None,effect=m[3],move=None)
    m=re.fullmatch(r'(相手の)?(.{1,20}?)の(.{1,30}?)と.{1,40}?の(.{1,20}?)が反応した!',body)
    if m and m[3] in stones and (n:=name(m[2])) and v7.distance(m[4],'ゼンブイリング')<=1:
        return event('MEGA_REACTION_CANDIDATE',name=n,side='opponent' if m[1] else None,stone=m[3],ring_raw=m[4],mega_completed=None)
    return None


def inspect(boxes,species,stones,method='full_frame'):
    body=text_rows(boxes)
    screen=v10.inspect(boxes,species)['screen_candidate'] if method=='full_frame' else 'NOT_APPLICABLE'
    event=parse(body['body'],species,stones) if screen=='UNKNOWN' else None
    return {**body,'screen':screen,'candidate':event,'event_emission':'DISABLED'}


def self_test():
    sp=['フラエッテ','ガオガエン','リザードン']; stones=['リザードナイトY']
    def p(t):return parse(v6.norm(t),sp,stones)
    def b(t,x,y,w=.06,h=.03):return {'text':t,'xyxy':[x,y,x+w,y+h]}
    rows=[b('相手のフラエッテの',.21,.744,.18,.034),b('とくこう',.21,.778,.03,.020),b('特攻',.21,.796,.036,.031),b('特防が上がった！',.26,.793,.15,.037)]
    return {
        'send':p('Aはプラエッテとガオガエンを繰り出した！')['kind']=='SEND_OUT_CANDIDATE',
        'two_stats':p('相手のフラエッテの特攻特防が上がった！')['stats']==['spa','spd'],
        'single_stat':p('相手のガオガエンの攻撃が下がった！')['stats']==['atk'],
        'repeat_stat_rejected':p('相手のガオガエンの攻撃攻撃が下がった！') is None,
        'effect_not_move':p('相手のガオガエンに効果はバツグンだ！')['move'] is None,
        'mega_not_completed':p('リザードンのリザードナイトYとAのゼンプイリングが反応した！')['mega_completed'] is None,
        'non_stone_rejected':p('リザードンのきあいのタスキとAのゼンブイリングが反応した！') is None,
        'ring_bad_rejected':p('リザードンのリザードナイトYとAの何かが反応した！') is None,
        'unknown_name_rejected':p('相手のABCの特攻が上がった！') is None,
        'extra_text_rejected':p('技一覧相手のガオガエンに効果はバツグンだ！') is None,
        'ruby_geometry':inspect(rows,sp,stones)['candidate']['stats']==['spa','spd'],
        'unrelated_small_text_preserved':1 not in text_rows([rows[0],b('とくこう',.50,.778,.03,.02),rows[2],rows[3]])['ruby_box_ids'],
        'menu_blocks':inspect(rows+[b('通信待機中',.46,.30)],sp,stones)['candidate'] is None,
        'crop_not_independent':inspect(rows,sp,stones,'direct_crop')['candidate'] is None,
        'never_confirmed':not p('相手のガオガエンに効果はバツグンだ！')['confirmed'],
    }
