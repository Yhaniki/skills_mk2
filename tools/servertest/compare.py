"""比對兩次 `servertest.py skills` 的結果（通常是基準版 0.7 對重構後的版本）。

用法：python compare.py 基準輸出資料夾 新版輸出資料夾

比對內容（都來自測試腳本寫的 skills_test.log，加上 errors_summary.txt）：
- CP   檢查點：每個 bot 的技能、狀態、MP（容許 ±1，每秒回復的時間點會有誤差）、無敵、護盾、
       是否活著／倒地、HUD 文字。血量不比：爆裂的瓦斯罐炸在 bot 腳邊，有沒有炸到每次不同
- DMG  測試腳本造成傷害時血量的變化量（要完全相同，用來驗證無敵與魔心護盾；倒地記成 incap）
- CPW  檢查點的全域效果：慢動作、EX 強光、魔法陣、霧
- HINT 每個情境裡每個 bot 的 HUD 文字變化順序
- CHAT 每個情境裡的聊天訊息順序
- 例外：依情境分組比對訊息與呼叫的函式
"""
import collections
import os
import re
import sys

LINE = re.compile(r"^L (\d\d/\d\d/\d{4} - \d\d:\d\d:\d\d): (.*)$")


def load(folder):
    data = {
        "cp": {}, "cpw": {}, "hint": collections.defaultdict(list), "chat": collections.defaultdict(list),
        "fail": [], "begin": [], "err": collections.defaultdict(list), "dmg": collections.defaultdict(list),
    }
    runs = collections.Counter()
    phase = "?"
    with open(os.path.join(folder, "skills_test.log"), encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            m = LINE.match(raw.rstrip("\n"))
            if not m:
                continue
            ts, body = m.groups()
            kind, _, rest = body.partition(" ")
            if kind == "PHASE":
                runs[rest] += 1
                phase = "%s#%d" % (rest, runs[rest])
                continue

            def key(path):  # main/explosion/act → main#1/explosion/act
                return phase + path[path.index("/"):]

            if kind == "BEGIN":
                data["begin"].append((ts, key(rest)))
            elif kind == "CP":
                path, bot, fields = (rest.split(" ", 2) + ["", ""])[:3]
                if fields == "none" or not fields:
                    data["cp"][(key(path), bot)] = {"none": "1"}
                else:
                    hint = fields.split(" hint=", 1)
                    d = dict(kv.split("=", 1) for kv in hint[0].split())
                    d["hint"] = hint[1] if len(hint) > 1 else ""
                    data["cp"][(key(path), bot)] = d
            elif kind == "CPW":
                path, fields = rest.split(" ", 1)
                data["cpw"][key(path)] = fields
            elif kind == "HINT":
                path, who, text = (rest.split(" ", 2) + [""])[:3]
                data["hint"][(key(path), who)].append(text)
            elif kind == "CHAT":
                path, who, text = (rest.split(" ", 2) + [""])[:3]
                data["chat"][key(path)].append("%s: %s" % (who, text))
            elif kind == "DMG":
                path, rest2 = rest.split(" ", 1)
                m2 = re.match(r"(\S+ \S+) hp=(-?\d+)->(-?\d+)", rest2)
                if m2:
                    before, after = int(m2.group(2)), int(m2.group(3))
                    rest2 = "%s %s" % (m2.group(1), "incap" if after > before else "%+d" % (after - before))
                data["dmg"][key(path)].append(rest2)
            elif kind == "FAIL":
                data["fail"].append(body)

    # 例外依時間歸到當時正在跑的情境
    p = os.path.join(folder, "errors_summary.txt")
    if os.path.exists(p):
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n")
                ts, sig = line[:21], line[22:]
                scen = "(開始前)"
                for bts, name in data["begin"]:
                    if bts <= ts:
                        scen = name
                data["err"][scen].append(sig)
    return data


def compare_cp(a, b):
    diffs = []
    for k in a.keys() | b.keys():
        if k[0].endswith("#?"):
            continue
        da = a.get(k)
        db = b.get(k)
        if da is None or db is None:
            diffs.append("%s %s：%s" % (k[0], k[1], "只有基準版有" if db is None else "只有新版有"))
            continue
        bad = []
        for f in sorted(da.keys() | db.keys()):
            va, vb = da.get(f), db.get(f)
            if f == "mp" and va is not None and vb is not None and abs(int(va) - int(vb)) <= 1:
                continue
            if f == "hp":
                continue
            if va != vb:
                bad.append("%s %s→%s" % (f, va, vb))
        if bad:
            diffs.append("%s %s：%s" % (k[0], k[1], "，".join(bad)))
    return sorted(diffs)


def compare_map(a, b, label):
    diffs = []
    for k in sorted(a.keys() | b.keys(), key=str):
        va, vb = a.get(k), b.get(k)
        if va != vb:
            diffs.append("%s %s\n    基準：%s\n    新版：%s" % (label, k, va, vb))
    return diffs


def main():
    base, new = load(sys.argv[1]), load(sys.argv[2])
    sections = [
        ("檢查點", compare_cp(base["cp"], new["cp"])),
        ("全域效果", compare_map(base["cpw"], new["cpw"], "CPW")),
        ("傷害", compare_map(dict(base["dmg"]), dict(new["dmg"]), "DMG")),
        ("HUD 文字順序", compare_map(dict(base["hint"]), dict(new["hint"]), "HINT")),
        ("聊天訊息順序", compare_map(dict(base["chat"]), dict(new["chat"]), "CHAT")),
        ("例外", compare_map(dict(base["err"]), dict(new["err"]), "ERR")),
    ]
    total = 0
    for title, diffs in sections:
        print("== %s：%d 項不同" % (title, len(diffs)))
        for d in diffs:
            print("  " + d)
        total += len(diffs)
    for name, d in (("基準版", base), ("新版", new)):
        for f in d["fail"]:
            print("%s 測試腳本 FAIL：%s" % (name, f))
    print("\n共 %d 項不同（檢查點 %d 個）" % (total, len(base["cp"])))
    sys.exit(1 if total else 0)


if __name__ == "__main__":
    main()
