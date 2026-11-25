#!/usr/bin/env python3
"""serve.py: 二重送信の構造対策 (送信済みの永続記録 + 終了イベント基準の対象判定)。
使い方: python3 prep_dupsent_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH).read()
EDITS = []

# 1. 対象範囲の判定を「ファイル時刻」から「試合の開始・終了イベント」へ
EDITS.append((
"""# 試合 (最新のファイルが起動時刻より新しい試合) だけを対象にする。
# 起動時点で既に終わっていた未送信分 (手動で処理済みの残りなど) を
# 起動のたびに聞き直さないため (実例: 2026-11-21
# battle_20261121_150535)。手動の --note では従来どおり全件を聞く。
# serve.py の自己再起動 (exec) ではプロセスが置き換わるため起動
# 時刻も更新されるが、その場合も対戦中の試合のログは再起動後に
# 書かれるため対象から漏れない
_PROCESS_STARTED_AT = time.time()""",
"""# 自動処理 (プロンプト・送信) の対象は、このプロセスの起動後に
# 始まった (または起動時点で進行中だった) 試合だけにする。起動
# 時点で既に終わっていた未送信分 (手動で処理済みの残りなど) を
# 起動のたびに聞き直さないため (実例: 2026-11-21
# battle_20261121_150535)。手動の --note では従来どおり全件を聞く。
# 判定はファイルの保存時刻では行わない。salvage の再保存や UI の
# 再送でファイル時刻が新しくなると、起動前に終わった試合が対象に
# 化けるため (実例: 2026-11-22 battle_20261122_071457 の二重送信)。
# 試合キー先頭の開始時刻 (JST) とプロセス起動時刻の比較、および
# 起動時点で進行中だった試合の控えで判定する
_PROCESS_STARTED_AT = time.time()


def _key_started_at(gate_key):
    \"\"\"試合キー先頭の開始時刻 (JST) を epoch 秒で返す。\"\"\"
    try:
        dt = datetime.strptime(gate_key[:15], "%Y%m%d_%H%M%S")
        return dt.replace(tzinfo=JST).timestamp()
    except Exception:
        return None


_STARTUP_BATTLE_KEY_UNSET = object()
_STARTUP_BATTLE_KEY_CACHE = _STARTUP_BATTLE_KEY_UNSET


def _startup_battle_key():
    \"\"\"起動時点で進行中だった試合のゲートキー (無ければ None)。

    serve.py が対戦中に再起動された場合、その試合はキー先頭の開始
    時刻だけでは「起動前に始まった試合」になり対象から漏れるため、
    起動直後の state.json の控えで補う。初回の判定時にだけ読み、
    以後は控えを使う (対戦終了後にログが保存されても覆らない)。\"\"\"
    global _STARTUP_BATTLE_KEY_CACHE
    if _STARTUP_BATTLE_KEY_CACHE is not _STARTUP_BATTLE_KEY_UNSET:
        return _STARTUP_BATTLE_KEY_CACHE
    key = None
    try:
        if _battle_in_progress():
            with open(STATE_JSON_PATH, encoding="utf-8") as f:
                battle = json.load(f).get("battle")
            if battle and _BATTLE_KEY_RE.match(str(battle)):
                key = _gate_key(str(battle))
    except Exception:
        key = None
    _STARTUP_BATTLE_KEY_CACHE = key
    return key"""))

# 2. _in_session_scope の新仕様
EDITS.append((
"""def _in_session_scope(gate_key, mtime):
    \"\"\"自動処理 (プロンプト・送信) の対象範囲内かどうか。

    起動後に終わった試合が原則で、自己再起動で引き継がれた試合も
    対象に含める。\"\"\"
    return mtime >= _PROCESS_STARTED_AT or gate_key in _CARRIED_NOTE_KEYS""",
"""def _in_session_scope(gate_key):
    \"\"\"自動処理 (プロンプト・送信) の対象範囲内かどうか。

    次のいずれかなら対象内: (1) 自己再起動で引き継がれた試合、
    (2) 起動時点で進行中だった試合、(3) 起動後に始まった試合
    (キー先頭の開始時刻がプロセス起動時刻以後)。ファイルの保存
    時刻は一切見ない (salvage の再保存や UI の再送で、起動前に
    終わった試合が対象に化けるのを防ぐため)。\"\"\"
    if not gate_key:
        return False
    if gate_key in _CARRIED_NOTE_KEYS:
        return True
    if gate_key == _startup_battle_key():
        return True
    started = _key_started_at(gate_key)
    return started is not None and started >= _PROCESS_STARTED_AT"""))

# 3. _note_blocking / _set_note_carry の呼び出し更新
EDITS.append((
"""        return any(_in_session_scope(p["key"], p.get("mtime", 0))
                   for p in list_pending_log_notes())""",
"""        return any(_in_session_scope(p["key"])
                   for p in list_pending_log_notes())"""))
EDITS.append((
"""        keys = sorted({p["key"] for p in list_pending_log_notes()
                       if _in_session_scope(p["key"], p.get("mtime", 0))})""",
"""        keys = sorted({p["key"] for p in list_pending_log_notes()
                       if _in_session_scope(p["key"])})"""))

# 4. 送信済みの永続記録 (sent_battles.json) の読み書きと更新
EDITS.append((
"""def _load_upload_state():
    if os.path.exists(LOG_STATE_PATH):
        try:
            return json.loads(open(LOG_STATE_PATH).read())
        except Exception:
            return {}
    return {}""",
"""def _load_upload_state():
    if os.path.exists(LOG_STATE_PATH):
        try:
            return json.loads(open(LOG_STATE_PATH).read())
        except Exception:
            return {}
    return {}


# 送信済みの試合の永続記録。ファイル単位の送信済み記録
# (uploaded.json) と目録 (logs_enc/index.json) は、内容が変化した
# ファイルを「未送信」と判定するため、送信後に UI から再送された
# ダメ計ログ (蓄積が増えた版) のような変化分が二重送信される
# (実例: 2026-11-22 battle_20261122_071457)。試合単位で「配送が
# 完了した」ことを記録し、その試合のファイルは再到着・salvage の
# 再保存・再起動があっても自動・手動を問わず二度と送らない
SENT_BATTLES_PATH = os.path.join(LOG_DIR, "sent_battles.json")


def _load_sent_battles():
    try:
        data = json.loads(open(SENT_BATTLES_PATH).read())
        if isinstance(data, list):
            return {k for k in data if isinstance(k, str)}
    except Exception:
        pass
    return set()


def _save_sent_battles(keys):
    try:
        with open(SENT_BATTLES_PATH, "w") as f:
            json.dump(sorted(keys), f)
    except OSError:
        pass


def _update_sent_battles(state, names, known):
    \"\"\"送信済みとして記録すべき試合を sent_battles.json へ反映する。

    確定ログ (final) がリポジトリの目録に載っている試合は配送が
    完了しているため、その時点で記録する (この記録が無い時代に
    送られた試合も、目録を見てここで取り込む)。確定ログの無い
    試合 (中断のみ) は、このサイクルの終了時点で未送信ファイルが
    残っていない場合に記録する。\"\"\"
    sent = _load_sent_battles()
    by_key = {}
    for n in names:
        key = _battle_key(n)
        if key is not None:
            by_key.setdefault(_gate_key(key), []).append(n)
    changed = False
    for gk, gnames in by_key.items():
        if gk in sent:
            continue
        has_final = any("_final" in n and n.endswith(".log")
                        for n in gnames)
        if has_final:
            final_known = any(
                "_final" in n and n.endswith(".log")
                and known.get(n) is not None
                and (known.get(n) == state.get(n)
                     or known.get(n) == _file_hash(
                         os.path.join(LOG_DIR, n)))
                for n in gnames)
            if final_known:
                sent.add(gk)
                changed = True
        elif all(state.get(n) == _file_hash(os.path.join(LOG_DIR, n))
                 for n in gnames):
            sent.add(gk)
            changed = True
    if changed:
        _save_sent_battles(sent)"""))

# 5. list_pending_log_notes: 送信済みの試合は備考待ちに数えない
EDITS.append((
"""    pending = []
    for key, names in sorted(groups.items()):
        if _note_exists(key):
            continue""",
"""    sent_battles = _load_sent_battles()
    pending = []
    for key, names in sorted(groups.items()):
        if key in sent_battles:
            # 送信済みの試合は閉じたものとして扱い、備考待ちにしない
            continue
        if _note_exists(key):
            continue"""))

# 6. _upload_logs_once_locked: 送信済み試合の除外と新スコープ判定
EDITS.append((
"""    names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    if not names:
        return
    state = _load_upload_state()
    group_mtimes = _battle_group_mtimes(names) if session_only else {}
    pending_all = []
    for n in names:
        if session_only:
            key = _battle_key(n)
            if (key is not None
                    and not _in_session_scope(
                        _gate_key(key),
                        group_mtimes.get(_gate_key(key), 0.0))):
                # 起動前から残っている試合は自動送信の対象外 (滞留分は
                # Mac 側にそのまま残し、手動の --note 経路でだけ扱う)
                continue""",
"""    names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    if not names:
        return
    state = _load_upload_state()
    sent_battles = _load_sent_battles()
    if sent_battles:
        # 送信済みの試合は、ファイルの再到着や salvage の再保存が
        # あっても自動・手動を問わず二度と送らない
        names = [n for n in names
                 if _battle_key(n) is None
                 or _gate_key(_battle_key(n)) not in sent_battles]
        if not names:
            return
    pending_all = []
    for n in names:
        if session_only:
            key = _battle_key(n)
            if (key is not None
                    and not _in_session_scope(_gate_key(key))):
                # 起動前から残っている試合は自動送信の対象外 (滞留分は
                # Mac 側にそのまま残し、手動の --note 経路でだけ扱う)
                continue"""))

# 7. 送信サイクルの末尾で送信済み記録を更新する
EDITS.append((
"""        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True""",
"""        _update_sent_battles(state, names, known)
        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True"""))

# 8. _battle_group_mtimes は廃止 (判定にファイル時刻を使わない)
EDITS.append((
"""def _battle_group_mtimes(names):
    \"\"\"試合キー (salvage 束ね済み) ごとの代表時刻を返す。

    代表時刻は、その試合のログ (.log) の最新時刻とする。推論過程
    ログのように、対戦の終了後に遅れて届くファイルがあっても、
    試合が「起動前に終わったものかどうか」の判定は変わらない
    (2026-11-21 のユーザー報告: 起動時に UI から再送された推論
    過程ログの時刻で、起動前の試合が送信対象に化けた)。ログの
    無い一式は、全ファイルの最新時刻で代用する。\"\"\"
    log_mtimes = {}
    all_mtimes = {}
    for n in names:
        key = _battle_key(n)
        if key is None:
            continue
        try:
            mt = os.path.getmtime(os.path.join(LOG_DIR, n))
        except OSError:
            continue
        gk = _gate_key(key)
        all_mtimes[gk] = max(all_mtimes.get(gk, 0.0), mt)
        if n.endswith(".log"):
            log_mtimes[gk] = max(log_mtimes.get(gk, 0.0), mt)
    return {gk: log_mtimes.get(gk, mt) for gk, mt in all_mtimes.items()}


""",
""""""))

# 9. _report_upload_completion のスコープ判定更新
EDITS.append((
"""    group_mtimes = _battle_group_mtimes(names) if session_only else {}
    held = set()
    other = 0
    for n in names:
        key = _battle_key(n)
        if (session_only and key is not None
                and not _in_session_scope(
                    _gate_key(key),
                    group_mtimes.get(_gate_key(key), 0.0))):
            continue""",
"""    held = set()
    other = 0
    for n in names:
        key = _battle_key(n)
        if (session_only and key is not None
                and not _in_session_scope(_gate_key(key))):
            continue"""))

# 10. prompt_for_pending_notes のスコープ判定更新
EDITS.append((
"""        if session_only and not _in_session_scope(p["key"], p.get("mtime", 0)):""",
"""        if session_only and not _in_session_scope(p["key"]):"""))

# 11. 受け取り表示の抑制をスコープ判定へ (推論過程ログ)
EDITS.append((
"""    # 起動前に終わった試合の推論過程ログが、UI の再送で起動時に
    # 届くことがある。保存はするが、起動時に過去分の処理が走って
    # いるように見える表示は出さない (2026-11-21 のユーザー指示)。
    # 判定はその試合のログの時刻で行う (対戦中の試合にはまだ
    # ログが無いため、通常どおり表示される)
    ended_before_start = False
    try:
        gk = _gate_key(battle)
        log_times = []
        for n in os.listdir(LOG_DIR):
            k = _battle_key(n)
            if k is not None and _gate_key(k) == gk and n.endswith(".log"):
                log_times.append(os.path.getmtime(os.path.join(LOG_DIR, n)))
        ended_before_start = bool(log_times) and max(log_times) < _PROCESS_STARTED_AT
    except OSError:
        ended_before_start = False""",
"""    # 起動前に終わった試合の推論過程ログが、UI の再送で起動時に
    # 届くことがある。保存はするが、起動時に過去分の処理が走って
    # いるように見える表示は出さない (2026-11-21 のユーザー指示)。
    # 判定は対象範囲の判定 (試合の開始時刻基準) で行う
    ended_before_start = not _in_session_scope(_gate_key(battle))"""))

# 12. 受け取り表示の抑制をスコープ判定へ (ダメ計ログ)
EDITS.append((
"""    # 推論過程ログと同じく、起動前に終わった試合分は保存だけして
    # 受け取り表示を出さない (起動時に過去分の処理が走っている
    # ように見せないため)
    ended_before_start = False
    try:
        gk = _gate_key(battle)
        log_times = []
        for n in os.listdir(LOG_DIR):
            k = _battle_key(n)
            if k is not None and _gate_key(k) == gk and n.endswith(".log"):
                log_times.append(os.path.getmtime(os.path.join(LOG_DIR, n)))
        ended_before_start = bool(log_times) and max(log_times) < _PROCESS_STARTED_AT
    except OSError:
        ended_before_start = False""",
"""    # 推論過程ログと同じく、起動前に終わった試合分は保存だけして
    # 受け取り表示を出さない (起動時に過去分の処理が走っている
    # ように見せないため)。判定は対象範囲の判定 (試合の開始時刻
    # 基準) で行う
    ended_before_start = not _in_session_scope(_gate_key(battle))"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for i, (old, new) in enumerate(EDITS):
    n = src.count(old)
    print(f"edit {i + 1}: anchor count = {n}")
    if n != 1:
        bad += 1
        continue
    if apply:
        src = src.replace(old, new, 1)
if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    open(PATH, "w").write(src)
    print("applied all", len(EDITS), "edits")
else:
    print("dry run ok:", len(EDITS), "edits ready")
