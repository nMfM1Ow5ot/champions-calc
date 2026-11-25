#!/usr/bin/env python3
# Harness T145: triage reproduction for battle_20261122_231107 turn 3 —
# the spe (faintOrder) event for a KO'd replacement that entered at the
# previous turn's end. The spe block scans battleLog after the current
# turn's |turn| anchor (fallback: the last |turn| line present); if the
# defender's |switch| line sits after that anchor in the array, the
# event is suppressed as "entered this turn".
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

anchor = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
if src.count(anchor) != 1:
    print("ABORT: anchor count", src.count(anchor))
    sys.exit(1)

tests = '''// T145 (battle_20261122_231107 切り分け): ターン2末のひんし交代で
// 登場した Charizard がターン3に行動前に倒れた場面の spe イベント。
// recordDamageEvent を直接呼び、battleLog の状態だけを変えて
// 生成条件 (slowEntered 判定) の効き方を確認する
func t145Setup(_ log: [String]) {
    resetAll()
    battleEvents = []
    lastExactHp = [:]
    lastDmgEventPrevExact = [:]
    battleLog = log
    currentTurn = 3
    monStates["p2:Basculegion-F"] = MonState(hpPercent: 80, hpText: "80/100")
    monStates["p1:Charizard"] = MonState(hpPercent: 100, hpText: "153/153")
    lastMoveLabel = "p2b: Basculegion-F"
    lastMoveName = "Muddy Water"
    actionSeq = 5
    lastMoveSeq = 5
    lastMoveMsgAt = Date()
}
func t145HasSpe() -> Bool { battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") } }
func t145HasDmg() -> Bool { battleEvents.contains { $0.contains("\\"k\\":\\"dmg\\"") } }
// A: |turn|3 がまだ battleLog に無い (フォールバックで |turn|2 が錨)
t145Setup(["|turn|2", "|switch|p1b: Charizard|Charizard|153/153"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145a no |turn|3 yet: dmg created, spe suppressed", t145HasDmg() && !t145HasSpe())
// B: |turn|3 はあるが、交代行がその後ろに登録されている (遅延登録)
t145Setup(["|turn|2", "|turn|3", "|switch|p1b: Charizard|Charizard|153/153"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145b switch registered after |turn|3: spe suppressed", t145HasDmg() && !t145HasSpe())
// C: 対照: 交代行が |turn|3 より前に登録されている通常形
t145Setup(["|turn|2", "|switch|p1b: Charizard|Charizard|153/153", "|turn|3"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145c switch before |turn|3: spe created", t145HasDmg() && t145HasSpe())

'''
src = src.replace(anchor, tests + anchor, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK T145 added")
