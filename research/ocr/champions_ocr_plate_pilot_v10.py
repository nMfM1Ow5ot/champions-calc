#!/usr/bin/env python3
"""Offline diagnostic v10: plate evidence independent of command menu.
Research only: no state updates; geometry specific to observed 1920x1080 layout.
"""
import re
import champions_ocr_replay_v6 as v6
import champions_ocr_evidence_v7 as v7
import champions_ocr_association_v8 as v8

# name and HP center windows (normalized, top-left origin)
SLOTS = {
    "own_left": ((.12,.86,.24,.925),(.16,.925,.28,.99),"own"),
    "own_right": ((.29,.86,.40,.925),(.34,.925,.46,.99),"own"),
    "opp_left": ((.59,.025,.70,.085),(.64,.085,.74,.145),"opp"),
    "opp_right": ((.76,.025,.87,.085),(.81,.085,.91,.145),"opp"),
}

def inside(box,rect):
    x,y=v6.center(box)
    return rect[0]<=x<=rect[2] and rect[1]<=y<=rect[3]

def inspect(boxes,species):
    v8.validate_boxes(boxes)
    def has(text,rect):
        return any(v6.norm(b["text"])==text and inside(b,rect) for b in boxes)
    base=v6.screen_evidence(boxes)
    m=base["markers"]
    command=m["command"] and (m["inspect"] or m["movehelp"])
    root=(has("ログを見る",(.07,.35,.22,.46))
          and has("様子を見る",(.74,.35,.93,.46))
          and (has("たたかう",(.75,.68,.93,.82)) or has("ポケモン",(.74,.86,.93,.99))))
    waiting=has("通信待機中",(.38,.23,.62,.38))
    flags=[name for name,ok in (
        ("STATUS_MENU",m["status_tabs"]),("COMMAND_ROOT",root),
        ("MOVE_MENU",command and m["movehelp"] and not root),
        ("COMMUNICATION_WAIT",waiting)) if ok]
    screen="CONFLICT" if len(flags)>1 else flags[0] if flags else "UNKNOWN"
    plates=[]
    if screen not in ("CONFLICT","STATUS_MENU"):
        for slot,(nr,hr,side) in SLOTS.items():
            names=[]
            for i,b in enumerate(boxes):
                if not inside(b,nr):continue
                n=v7.name_evidence(b["text"],species)
                if n["status"] in ("EXACT_TEXT","SUGGESTED") and len(n["best_candidates"])==1 and n["best_distance"]<=1:
                    names.append((i,n))
            values=[]
            for j,b in enumerate(boxes):
                if not inside(b,hr):continue
                s=v6.norm(b["text"])
                if side=="own":
                    vals=v6.hp_candidates(s)
                else:
                    vals=[s] if re.fullmatch(r"[0-9]{1,3}%",s) and int(s[:-1])<=100 else []
                if len(vals)==1:values.append((j,vals[0]))
            if len(names)==len(values)==1:
                i,n=names[0];j,val=values[0]
                plates.append({"slot":slot,"name":n,"hp_raw":boxes[j]["text"],"hp_candidate":val,
                               "box_ids":[i,j],"confirmed":False})
    # preserve evidence if overlap or future geometry changes permit reuse
    ids=[i for plate in plates for i in plate["box_ids"]]
    if len(ids)!=len(set(ids)):plates=[]
    return {"screen_candidate":screen,"screen_flags":flags,"hp_candidates":plates,
            "event_emission":"DISABLED"}

def self_test():
    def b(t,x,y):return {"text":t,"xyxy":[x-.01,y-.01,x+.01,y+.01]}
    s=["リザードン","フシギバナ","ゴリランダー","フラエッテ"]
    root=[b("ログを見る",.14,.41),b("様子を見る",.85,.41),b("たたかう",.85,.75)]
    wait=[b("通信待機中",.5,.31)]
    own=[b("リザードン",.17,.90),b("72/153",.22,.95)]
    opp=[b("ゴリランダー",.64,.06),b("100%",.69,.11)]
    run=lambda x:inspect(x,s)
    return {
        "root_without_command":run(root)["screen_candidate"]=="COMMAND_ROOT",
        "waiting":run(wait)["screen_candidate"]=="COMMUNICATION_WAIT",
        "conflict":run(root+wait)["screen_candidate"]=="CONFLICT",
        "unknown_not_command":run(own)["screen_candidate"]=="UNKNOWN",
        "own_outside_command":len(run(own)["hp_candidates"])==1,
        "opponent_outside_command":len(run(opp)["hp_candidates"])==1,
        "missing_percent_rejected":not run([opp[0],b("100",.69,.11)])["hp_candidates"],
        "name_typo_candidate":run([b("フシギパナ",.35,.90),b("57/157",.40,.95)])["hp_candidates"][0]["name"]["status"]=="SUGGESTED",
        "multiple_hp_rejected":not run(own+[b("70/153",.24,.95)])["hp_candidates"],
        "no_cross_slot":not run([own[0],b("57/157",.40,.95)])["hp_candidates"],
        "no_state_update":run(root+own)["event_emission"]=="DISABLED",
    }
