#!/usr/bin/env python3
# Harness support for the battle_20261123_052626 fix round (T151a-e):
# - FUNCS: extract isMoveListText and fieldLineWithAttribution
# - prelude emitLog copy: mirror the fieldLineWithAttribution call at its head
# - driver: append T151a-e after T150e
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
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

rep("'fieldLineForAbility', 'annotateFieldLineFromAbility',",
    "'fieldLineForAbility', 'annotateFieldLineFromAbility', 'fieldLineWithAttribution', 'isMoveListText',",
    "FUNCS")

rep("""    if winLogged { startBattleLog() }
    // 本体と同一: あり得ない特性行・技行のガードと、技行前のひんし行フラッシュ""",
    """    if winLogged { startBattleLog() }
    let line = fieldLineWithAttribution(line)
    // 本体と同一: あり得ない特性行・技行のガードと、技行前のひんし行フラッシュ""",
    "prelude emitLog mirror")

rep('''check("T150e detect activate emitted", battleLog.contains("|-activate|p1a: Sylveon|move: Detect"))''',
    '''check("T150e detect activate emitted", battleLog.contains("|-activate|p1a: Sylveon|move: Detect"))
// T151 (battle_20261123_052626): 技リスト誤認 / 勝敗文の化け / Stamina 帰属 / block 行 / 天候の付け直し
// a: コマンド画面の技リスト連結文は技リストと判定し、実告知と種族名に重なる技名は数えない
moveNameOrig[normalize("てだすけ")] = "てだすけ"; moveJa2En["てだすけ"] = "Helping Hand"
moveNameOrig[normalize("サイコキネシス")] = "サイコキネシス"; moveJa2En["サイコキネシス"] = "Psychic"
moveNameOrig[normalize("でんじは")] = "でんじは"; moveJa2En["でんじは"] = "Thunder Wave"
moveNameOrig[normalize("つるぎのまい")] = "つるぎのまい"; moveJa2En["つるぎのまい"] = "Swords Dance"
check("T151a move list text detected", isMoveListText("リキキリンサイコキネシスてだすけ10まんボルトでんじは"))
check("T151a real announcement not a list", !isMoveListText("リキキリンの てだすけ！"))
check("T151a species-substring move not counted", !isMoveListText("カイリキーの つるぎのまい！"))
// b: 勝ち文の「勝負」が「勝質」に崩れても |win| になる
resetAll()
_ = translateBattleMessage("Kiwiとの勝質に勝った！")
check("T151b garbled win text produces win", battleLog.contains("|win|p1") && winLogged)
// c: 被ダメ直後の防御 +1 上昇に Stamina の特性行が先行する
resetAll()
speciesAbilityMap["Archaludon"] = ["Stamina"]
monStates["p2:Archaludon"] = MonState()
lastMoveLabel = "p1a: Garchomp"; lastMoveName = "Earth Power"; lastMoveMsgAt = Date()
damagedBySeq[actionSeq, default: []].insert("p2a: Archaludon")
checkBoostText(text: "相手のブリジュラスの 防御が上がった！", side: "p2", speciesEn: "Archaludon", slot: "p2a")
check("T151c stamina ability precedes boost", battleLog.contains("|-ability|p2a: Archaludon|Stamina") && battleLog.contains("|-boost|p2a: Archaludon|def|1") && battleLog.firstIndex(of: "|-ability|p2a: Archaludon|Stamina")! < battleLog.firstIndex(of: "|-boost|p2a: Archaludon|def|1")!)
// d: まもる成功文に block 行と activate 行の両方が付く
resetAll()
logStarted = true
currentTurn = 3
lastSingleActAt = [:]
lastSlots = ["oppA": SlotState(speciesEn: "Archaludon", hpPercent: 44)]
emitLog("|move|p2a: Archaludon|Protect")
_ = translateBattleMessage("相手のブリジュラスは 攻撃から 身を守った！")
check("T151d block line emitted", battleLog.contains("|-block|p2a: Archaludon|move: Protect"))
check("T151d activate line emitted", battleLog.contains("|-activate|p2a: Archaludon|move: Protect"))
// e: 特性行が先行する配置でも天候行に [from] が付く。技による開始では付かない
resetAll()
if !speciesDict.contains(where: { $0.en == "Pelipper" }) { speciesDict.append(E("ペリッパー", "Pelipper")) }
speciesAbilityMap["Pelipper"] = ["Keen Eye", "Drizzle", "Hydration"]
emitLog("|-ability|p2b: Pelipper|Drizzle")
emitLog("|-weather|Rain Dance")
check("T151e weather attributed when ability precedes", battleLog.contains("|-weather|Rain Dance|[from] ability: Drizzle|[of] p2b: Pelipper"))
resetAll()
speciesAbilityMap["Pelipper"] = ["Keen Eye", "Drizzle", "Hydration"]
emitLog("|move|p2b: Pelipper|Rain Dance")
emitLog("|-ability|p2b: Pelipper|Drizzle")
emitLog("|-weather|Rain Dance")
check("T151e no attribution when set by move", battleLog.contains("|-weather|Rain Dance") && !battleLog.contains("|-weather|Rain Dance|[from]"))''',
    "T151 tests")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
