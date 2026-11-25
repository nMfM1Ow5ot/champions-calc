#!/usr/bin/env python3
# serve.py: resumable log upload (comprehensive-chat instruction,
# user instruction 2026-11-22). A failed cycle resumes with only the
# unsent files: per-file progress is persisted as each file lands,
# uploaded-but-unindexed files are tracked in index_pending.json and
# merged into the index by a later cycle, 409s on file/index PUTs are
# retried once with a fresh sha (index: merged over the fresh copy),
# and sent-battle marking happens only after the index PUT succeeds.
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ---- helpers: upload-state save + index-pending record + PUT retries ----
rep("helpers",
    """def _load_upload_state():""",
    """def _save_upload_state(state):
    try:
        with open(LOG_STATE_PATH, "w") as f:
            json.dump(state, f)
    except OSError:
        pass


def _index_pending_path():
    # パスは LOG_DIR から都度導く (定数にすると、テストが LOG_DIR を
    # 差し替えたときに実ファイルを汚染する。sent_battles と同じ)
    return os.path.join(LOG_DIR, "index_pending.json")


def _load_index_pending():
    try:
        data = json.loads(open(_index_pending_path()).read())
        if isinstance(data, list):
            return [n for n in data if isinstance(n, str)]
    except Exception:
        pass
    return []


def _save_index_pending(names):
    try:
        with open(_index_pending_path(), "w") as f:
            json.dump(sorted(set(names)), f)
    except OSError:
        pass


def _put_log_file(path, content, token, message):
    \"\"\"ログファイルの PUT。sha の競合 (409) は、sha を取り直して
    1 回だけ再試行する\"\"\"
    _, sha = _gh_get_file(path, token)
    try:
        return _gh_put_file(path, content, token, message, sha=sha)
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise
        _, sha = _gh_get_file(path, token)
        return _gh_put_file(path, content, token, message, sha=sha)


def _put_log_index(index, token, index_sha, our_entries):
    \"\"\"目録の PUT。409 の場合は目録を取り直し、このサイクルで
    送った分のエントリだけを重ねて 1 回だけ再試行する\"\"\"
    body = json.dumps(index, ensure_ascii=False, indent=1).encode()
    try:
        return _gh_put_file("logs_enc/index.json", body, token,
                            "update battle log index", sha=index_sha)
    except urllib.error.HTTPError as e:
        if e.code != 409:
            raise
        fresh_bytes, fresh_sha = _gh_get_file("logs_enc/index.json", token)
        fresh = {"files": []}
        if fresh_bytes:
            try:
                fresh = json.loads(fresh_bytes.decode())
            except Exception:
                fresh = {"files": []}
        merged = {e.get("name"): e for e in fresh.get("files", [])}
        for n, entry in our_entries.items():
            merged[n] = entry
        fresh["files"] = sorted(merged.values(),
                                 key=lambda e: e["name"])
        body = json.dumps(fresh, ensure_ascii=False, indent=1).encode()
        return _gh_put_file("logs_enc/index.json", body, token,
                            "update battle log index", sha=fresh_sha)


def _load_upload_state():""")

# ---- early return also wakes for index-pending repairs ----
rep("early return",
    """    # デバッグ同梱の掃除は 1 日 1 回まで (送信が無い日でもその回だけ目録を見る)
    prune_due = _log_prune_done_date != datetime.now(JST).date()
    if not pending and not prune_due:
        return""",
    """    # デバッグ同梱の掃除は 1 日 1 回まで (送信が無い日でもその回だけ目録を見る)
    prune_due = _log_prune_done_date != datetime.now(JST).date()
    # 前回までのサイクルでファイル自体は送れたのに目録への反映が
    # 失敗した分は、未送信分として扱い、目録の修復だけを行う
    index_pending = [n for n in _load_index_pending() if n in names]
    if not pending and not prune_due and not index_pending:
        return""")

# ---- per-file loop: 409-tolerant PUT + incremental progress ----
rep("file loop",
    """        known = {e.get("name"): e.get("sha256") for e in index.get("files", [])}
        changed_index = False
        sent_battle = 0
        for n, data, h in pending:
            if known.get(n) == h:
                state[n] = h
                continue
            enc = _encrypt_log(data)
            if enc is None:
                raise RuntimeError("暗号化に失敗しました (team_key.txt を確認してください)")
            _, enc_sha = _gh_get_file("logs_enc/" + n + ".enc", token)
            _gh_put_file("logs_enc/" + n + ".enc", enc, token,
                         f"battle log {n}", sha=enc_sha)
            index["files"] = [e for e in index.get("files", [])
                              if e.get("name") != n]
            index["files"].append({
                "name": n, "sha256": h,
                "uploaded_at": datetime.now(JST).isoformat()})
            known[n] = h
            state[n] = h
            changed_index = True""",
    """        known = {e.get("name"): e.get("sha256") for e in index.get("files", [])}
        changed_index = False
        sent_battle = 0
        our_entries = {}
        # 目録への反映が済んでいない既送信分の修復: ファイルの再送は
        # せず、目録のエントリだけを足す
        for n in index_pending:
            h = state.get(n)
            if h is None or known.get(n) == h:
                continue
            if _file_hash(os.path.join(LOG_DIR, n)) != h:
                continue
            entry = {"name": n, "sha256": h,
                     "uploaded_at": datetime.now(JST).isoformat()}
            index["files"] = [e for e in index.get("files", [])
                              if e.get("name") != n]
            index["files"].append(entry)
            our_entries[n] = entry
            known[n] = h
            changed_index = True
        for n, data, h in pending:
            if known.get(n) == h:
                state[n] = h
                continue
            enc = _encrypt_log(data)
            if enc is None:
                raise RuntimeError("暗号化に失敗しました (team_key.txt を確認してください)")
            _put_log_file("logs_enc/" + n + ".enc", enc, token,
                          f"battle log {n}")
            entry = {
                "name": n, "sha256": h,
                "uploaded_at": datetime.now(JST).isoformat()}
            index["files"] = [e for e in index.get("files", [])
                              if e.get("name") != n]
            index["files"].append(entry)
            our_entries[n] = entry
            known[n] = h
            state[n] = h
            changed_index = True
            # 進捗はファイル単位でその場で永続化する。途中で失敗して
            # サイクルが中断しても、次回は未送信分から再開する
            # (送信済みファイルの再送はしない)
            _save_upload_state(state)
            if n not in index_pending:
                index_pending.append(n)
                _save_index_pending(index_pending)""")

# ---- tail: index PUT (409 merge retry) -> clear pending -> marking ----
rep("cycle tail",
    """        _update_sent_battles(state, names, known)
        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True
            _log_prune_done_date = datetime.now(JST).date()
        if changed_index:
            index["files"].sort(key=lambda e: e["name"])
            _gh_put_file("logs_enc/index.json",
                         json.dumps(index, ensure_ascii=False, indent=1).encode(),
                         token, "update battle log index", sha=index_sha)
        with open(LOG_STATE_PATH, "w") as f:
            json.dump(state, f)
        _log_last_error = ""
        if sent_battle:
            _report_upload_completion(state, session_only)""",
    """        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True
            _log_prune_done_date = datetime.now(JST).date()
        if changed_index:
            index["files"].sort(key=lambda e: e["name"])
            _put_log_index(index, token, index_sha, our_entries)
        # 目録への反映が確認できた分は、修復待ちから外す (既に目録に
        # 載っていた分もここで掃除する)
        if index_pending:
            remaining = [n for n in index_pending
                         if known.get(n) != state.get(n)]
            if len(remaining) != len(index_pending):
                index_pending = remaining
                _save_index_pending(index_pending)
        _save_upload_state(state)
        # 送信済みの記録は、目録への反映まで成功したサイクルでのみ
        # 行う (ファイルだけ送れて目録が失敗した試合を、完了として
        # 記録してしまうと二度と目録に載らなくなるため)
        _update_sent_battles(state, names, known)
        _log_last_error = ""
        if sent_battle:
            _report_upload_completion(state, session_only)""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
