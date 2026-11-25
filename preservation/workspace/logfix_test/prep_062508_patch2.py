#!/usr/bin/env python3
# Second patch for the 062508 round: maxReadPlausible helper (T133f
# regression fix) + recoil event move-name plumbing (T157).
import re, sys, datetime

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print(f"ABORT {tag}: anchor count = {n}")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

# P1: the plausibility helper, placed before parseMineHPText
rep('''// knownMax: 判明済みの最大HP (対戦中の記録 or チーム登録の実数値)。現在値だけ''',
    '''// 読みの最大値が、既知の最大値の桁レベルの誤読としてあり得るか。
// 先頭桁の脱落 (145 -> 45) は断片読みとして許し、小さな差は桁の
// 誤読として許す。それ以外の大差は、数字の連結等の化けで割合
// 自体が作られている疑いが強い (実例: 2026-11-23
// battle_20261123_062508、177/177 が「177277」と読まれ最大値が
// 277 になった)
func maxReadPlausible(readMax: Int, knownMax: Int) -> Bool {
    if readMax == knownMax { return true }
    if knownMax >= 100 && readMax == knownMax % 100 { return true }
    return abs(readMax - knownMax) <= 36
}

// knownMax: 判明済みの最大HP (対戦中の記録 or チーム登録の実数値)。現在値だけ''',
    "P1 helper")

# P2: processPlates gate uses the helper
rep('''            if abs(readMax - knownMax) > 36, let prevSlot = lastSlots[plate.name],''',
    '''            if !maxReadPlausible(readMax: readMax, knownMax: knownMax), let prevSlot = lastSlots[plate.name],''',
    "P2 rescale gate")

# P3: parsePlate gate uses the helper
rep('''                    if let km = knownMax, let mx = r.max, abs(mx - km) > 36 { continue }''',
    '''                    if let km = knownMax, let mx = r.max, !maxReadPlausible(readMax: mx, knownMax: km) { continue }''',
    "P3 parsePlate gate")

# P4: recordRecoilEvent takes the classified move name
rep('''func recordRecoilEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) {''',
    '''func recordRecoilEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, moveName: String = "") {''',
    "P4a recoil signature")
rep('''    var ev = "{\\"k\\":\\"dmg\\",\\"turn\\":\\(currentTurn),\\"atk\\":\\"\\(jsonEscape(label))\\",\\"def\\":\\"\\(jsonEscape(label))\\",\\"move\\":\\"\\(jsonEscape(lastMoveName))\\",\\"crit\\":false"''',
    '''    var ev = "{\\"k\\":\\"dmg\\",\\"turn\\":\\(currentTurn),\\"atk\\":\\"\\(jsonEscape(label))\\",\\"def\\":\\"\\(jsonEscape(label))\\",\\"move\\":\\"\\(jsonEscape(moveName.isEmpty ? lastMoveName : moveName))\\",\\"crit\\":false"''',
    "P4b recoil move")

# P5: emitDamageLine tracks which move the recoil classification used
rep('''        var selfClassified = false   // 自分の技の反動として分類できたら、推定用イベントも出す''',
    '''        var selfClassified = false   // 自分の技の反動として分類できたら、推定用イベントも出す
        var recoilMove = ""          // 反動と分類した技 (遅延帰属では本人の直近の技)''',
    "P5a recoilMove local")
rep('''                } else if recoilMoves.contains(lastMoveName) {
                    fromCode = "move: \\(lastMoveName)"
                    selfClassified = true
                } else if (11...18).contains(drop) {''',
    '''                } else if recoilMoves.contains(lastMoveName) {
                    fromCode = "move: \\(lastMoveName)"
                    selfClassified = true
                    recoilMove = lastMoveName
                } else if (11...18).contains(drop) {''',
    "P5b immediate recoil")
rep('''               (1...50).contains(effFrom - toPct) {
                fromCode = "move: \\(own.move)"
                selfClassified = true
            }''',
    '''               (1...50).contains(effFrom - toPct) {
                fromCode = "move: \\(own.move)"
                selfClassified = true
                recoilMove = own.move
            }''',
    "P5c late recoil")
rep('''        if selfClassified {
            recordRecoilEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        }''',
    '''        if selfClassified {
            recordRecoilEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, moveName: recoilMove)
        }''',
    "P5d recoil call")

stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
