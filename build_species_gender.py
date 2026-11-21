#!/usr/bin/env python3
"""各種族の性別を data/species_types.json の "gender" に書き込む
(ローカル専用、同期対象外)。

性別は種族 (baseSpecies) 単位の性質なので、@smogon/calc の baseSpecies で
種族に寄せ、PokéAPI の公式 CSV (pokemon_species.csv) の gender_rate を引く。
gender_rate: -1 = 性別なし、0 = ♂のみ、8 = ♀のみ、それ以外は両性。
性別フォルム (Indeedee-F、Meowstic-M-Mega 等) は名前の -F / -M で上書きする。
Showdown の pokedex.json は genderRatio が欠ける種族が多く使えない。
別ファイルではなく species_types.json に同梱するのは、Mac 側の同期
(sync_ui.py の MANIFEST) が固定リスト方式で、新規ファイルは次回 ZIP
まで届かないため。
"""
import csv
import json
import os
import re
import subprocess

BASE = os.path.dirname(os.path.abspath(__file__))
CSV_DIR = os.path.join(BASE, "preview_eval", "pokeapi_csv")
CSV_URL = "https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/pokemon_species.csv"


def base_species_map():
    js = """
const {SPECIES} = require('@smogon/calc');
const dex = require('./data/regulation.json').species;
const out = {};
for (const name of dex) {
  const sp = SPECIES[9][name];
  out[name] = sp ? (sp.baseSpecies || name) : null;
}
console.log(JSON.stringify(out));
"""
    r = subprocess.run(["node", "-e", js], cwd=BASE, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(r.stderr)
    return json.loads(r.stdout)


def slug(s):
    s = s.lower().replace("’", "").replace("'", "").replace(".", "").replace(":", "")
    return re.sub(r"\s+", "-", s)


def main():
    path = os.path.join(CSV_DIR, "pokemon_species.csv")
    if not os.path.exists(path):
        os.makedirs(CSV_DIR, exist_ok=True)
        subprocess.run(["curl", "-s", "--max-time", "60", "-o", path, CSV_URL], check=True)
    rates = {}
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            rates[row["identifier"]] = int(row["gender_rate"])
    out, missing = {}, []
    for name, base in base_species_map().items():
        rate = rates.get(slug(base)) if base else None
        if rate is None and base:
            # baseSpecies が兄弟フォルムを指す種族 (Aegislash 系: base は Aegislash-Blade) は
            # CSV の identifier 'aegislash' と一致しないため、'-' で切り詰めて再照合する。
            s = slug(base)
            while "-" in s:
                s = s.rsplit("-", 1)[0]
                if s in rates:
                    rate = rates[s]
                    break
        if rate is None:
            missing.append(name)
            continue
        out[name] = ["N"] if rate == -1 else ["M"] if rate == 0 else ["F"] if rate == 8 else ["M", "F"]
        # 性別フォルムは名前が性別を固定する
        if re.search(r"-F(-|$)", name):
            out[name] = ["F"]
        elif re.search(r"-M(-|$)", name):
            out[name] = ["M"]
    if missing:
        raise SystemExit(f"対応付けできない種族があります: {missing}")
    types_path = os.path.join(BASE, "data", "species_types.json")
    with open(types_path, encoding="utf-8") as f:
        types_data = json.load(f)
    for name, genders in out.items():
        types_data[name]["gender"] = genders
    with open(types_path, "w", encoding="utf-8") as f:
        json.dump(types_data, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"{len(out)} 種族分の gender を species_types.json に書き込みました")


if __name__ == "__main__":
    main()
