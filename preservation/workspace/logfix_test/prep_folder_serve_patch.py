#!/usr/bin/env python3
# serve.py patch: per-battle folders under logs/. Writers put new
# files into logs/battle_<key>/; every reader resolves names
# through a path map that prefers the folder layout and still
# accepts the legacy flat layout; a startup migration moves the
# flat stock into folders (move only, never deletes). Upload
# names stay flat. User instruction via the comprehensive chat,
# 2026-11-23.
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count = {n} (expected {count})")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

# G1: folder helpers + migration, before _note_name
rep('''def _note_name(key):''',
    '''def _battle_folder_path(key):
    """その試合のフォルダ (logs/battle_<key>/)。"""
    return os.path.join(LOG_DIR, f"battle_{key}")


def _log_file_map():
    """ファイル名 (平坦名) → 実パスの対応。試合フォルダ内を正とし、
    直下に残った従来配置も拾う (移行中の読み取り互換のため)。"""
    found = {}
    if not os.path.isdir(LOG_DIR):
        return found
    for name in sorted(os.listdir(LOG_DIR)):
        path = os.path.join(LOG_DIR, name)
        if os.path.isdir(path):
            for sub in sorted(os.listdir(path)):
                sub_path = os.path.join(path, sub)
                if os.path.isfile(sub_path):
                    found[sub] = sub_path
    for name in sorted(os.listdir(LOG_DIR)):
        path = os.path.join(LOG_DIR, name)
        if os.path.isfile(path):
            found.setdefault(name, path)
    return found


def _path_of(paths, name):
    return paths.get(name) or os.path.join(LOG_DIR, name)


def _folder_name_for(name):
    """直下のファイルが属するフォルダ名 (属さなければ None)。"""
    if name.startswith("preview_test_"):
        stem = name[len("preview_test_"):].rsplit(".", 1)[0]
        return f"preview_test_{stem}"
    bk = _battle_key(name)
    if bk is None:
        return None
    return f"battle_{bk}"


def _migrate_logs_into_folders():
    """直下に残った試合ファイルを試合フォルダへ寄せる (起動時)。
    移動のみで削除はしない。同名が既にフォルダ内にあれば、直下の
    分はそのまま残す (読み取りは両配置に対応する)。"""
    if not os.path.isdir(LOG_DIR):
        return
    for name in sorted(os.listdir(LOG_DIR)):
        src_path = os.path.join(LOG_DIR, name)
        if not os.path.isfile(src_path):
            continue
        folder = _folder_name_for(name)
        if folder is None:
            continue
        dest_dir = os.path.join(LOG_DIR, folder)
        dest = os.path.join(dest_dir, name)
        if os.path.exists(dest):
            continue
        try:
            os.makedirs(dest_dir, exist_ok=True)
            os.replace(src_path, dest)
        except OSError:
            continue


def _note_name(key):''',
    "G1 helpers + migration")

# G2: _unsent_ready_battle_keys scans the map
rep('''        groups = {}
        for name in sorted(os.listdir(LOG_DIR)):
            if not _is_upload_target(name):
                continue
            bk = _battle_key(name)
            if bk is None:
                continue''',
    '''        groups = {}
        for name in sorted(_log_file_map()):
            if not _is_upload_target(name):
                continue
            bk = _battle_key(name)
            if bk is None:
                continue''',
    "G2 unsent scan")

# G3: _battle_in_progress scans the map
rep('''    try:
        names = os.listdir(LOG_DIR)
    except OSError:
        return False''',
    '''    try:
        names = list(_log_file_map())
    except OSError:
        return False''',
    "G3 in-progress scan")

# G4: _note_exists checks the folder, then the legacy flat path
rep('''def _note_exists(key):
    return os.path.exists(os.path.join(LOG_DIR, _note_name(key)))''',
    '''def _note_exists(key):
    return (os.path.exists(os.path.join(_battle_folder_path(key),
                                        _note_name(key)))
            or os.path.exists(os.path.join(LOG_DIR, _note_name(key))))''',
    "G4 note exists")

# G5: inference/calclog writers go into the battle folder
rep('''    os.makedirs(LOG_DIR, exist_ok=True)
    name = f"battle_{battle}_inference.json"
    with open(os.path.join(LOG_DIR, name), "wb") as f:''',
    '''    folder = _battle_folder_path(battle)
    os.makedirs(folder, exist_ok=True)
    name = f"battle_{battle}_inference.json"
    with open(os.path.join(folder, name), "wb") as f:''',
    "G5a inference writer")
rep('''    os.makedirs(LOG_DIR, exist_ok=True)
    name = f"battle_{battle}_calclog.json"
    with open(os.path.join(LOG_DIR, name), "wb") as f:''',
    '''    folder = _battle_folder_path(battle)
    os.makedirs(folder, exist_ok=True)
    name = f"battle_{battle}_calclog.json"
    with open(os.path.join(folder, name), "wb") as f:''',
    "G5b calclog writer")

# G6: _update_sent_battles resolves paths through the map
rep('''    sent = _load_sent_battles()
    by_key = {}''',
    '''    sent = _load_sent_battles()
    paths = _log_file_map()
    by_key = {}''',
    "G6a update-sent paths")
rep('''                and (known.get(n) == state.get(n)
                     or known.get(n) == _file_hash(
                         os.path.join(LOG_DIR, n)))''',
    '''                and (known.get(n) == state.get(n)
                     or known.get(n) == _file_hash(
                         _path_of(paths, n)))''',
    "G6b update-sent hash 1")
rep('''        elif all(state.get(n) == _file_hash(os.path.join(LOG_DIR, n))''',
    '''        elif all(state.get(n) == _file_hash(_path_of(paths, n))''',
    "G6c update-sent hash 2")

# G7: _pending_note_keys scans and reads through the map
rep('''    state = _load_upload_state()
    groups = {}
    for name in sorted(os.listdir(LOG_DIR)):''',
    '''    state = _load_upload_state()
    paths = _log_file_map()
    groups = {}
    for name in sorted(paths):''',
    "G7a pending scan")
rep('''                mtime = max(mtime, os.path.getmtime(os.path.join(LOG_DIR, n)))''',
    '''                mtime = max(mtime, os.path.getmtime(_path_of(paths, n)))''',
    "G7b pending mtime")
rep('''            unsent = [n for n in log_names
                      if state.get(n) != _file_hash(os.path.join(LOG_DIR, n))]''',
    '''            unsent = [n for n in log_names
                      if state.get(n) != _file_hash(_path_of(paths, n))]''',
    "G7c pending unsent 1")
rep('''            unsent = [n for n in names
                      if state.get(n) != _file_hash(os.path.join(LOG_DIR, n))]''',
    '''            unsent = [n for n in names
                      if state.get(n) != _file_hash(_path_of(paths, n))]''',
    "G7d pending unsent 2")
rep('''                text = open(os.path.join(LOG_DIR, n), encoding="utf-8").read()''',
    '''                text = open(_path_of(paths, n), encoding="utf-8").read()''',
    "G7e pending read")

# G8: note writer goes into the battle folder
rep('''    os.makedirs(LOG_DIR, exist_ok=True)
    path = os.path.join(LOG_DIR, _note_name(key))''',
    '''    folder = _battle_folder_path(key)
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, _note_name(key))''',
    "G8 note writer")

# G9: the upload cycle scans and reads through the map
rep('''    names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    if not names:
        return
    state = _load_upload_state()''',
    '''    paths = _log_file_map()
    names = sorted(n for n in paths if _is_upload_target(n))
    if not names:
        return
    state = _load_upload_state()''',
    "G9a cycle scan")
rep('''        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(data).hexdigest()
        if state.get(n) != h:
            pending_all.append((n, data, h))''',
    '''        try:
            data = open(_path_of(paths, n), "rb").read()
        except OSError:
            continue
        h = hashlib.sha256(data).hexdigest()
        if state.get(n) != h:
            pending_all.append((n, data, h))''',
    "G9b cycle read")
rep('''            if _file_hash(os.path.join(LOG_DIR, n)) != h:''',
    '''            if _file_hash(_path_of(paths, n)) != h:''',
    "G9c cycle recheck")

# G10: the completion-display scan reads through the map
rep('''    try:
        names = sorted(n for n in os.listdir(LOG_DIR) if _is_upload_target(n))
    except OSError:
        return''',
    '''    paths = _log_file_map()
    try:
        names = sorted(n for n in paths if _is_upload_target(n))
    except OSError:
        return''',
    "G10a display scan")
rep('''        try:
            data = open(os.path.join(LOG_DIR, n), "rb").read()
        except OSError:
            continue
        if state.get(n) == hashlib.sha256(data).hexdigest():''',
    '''        try:
            data = open(_path_of(paths, n), "rb").read()
        except OSError:
            continue
        if state.get(n) == hashlib.sha256(data).hexdigest():''',
    "G10b display read")

# G11: run the migration at startup
rep('''    check_log_token()''',
    '''    check_log_token()
    # 直下に残った試合ファイルを試合フォルダへ寄せる (配置の移行)
    try:
        _migrate_logs_into_folders()
    except Exception:
        pass''',
    "G11 startup migration")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
