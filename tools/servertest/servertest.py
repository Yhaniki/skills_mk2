"""在本機 L4D2 dedicated server 上自動測試 skills_mk2，不需要人進遊戲。

用法：
    python servertest.py smoke  --smx 要測的.smx --out 輸出資料夾 [--server 伺服器資料夾]
    python servertest.py skills --smx 測試版.smx --out 輸出資料夾 [--server 伺服器資料夾]
    python servertest.py phase  --smx 測試版.smx --out 輸出資料夾 --phase 階段 [--phase 階段 ...]

--server 也可以用環境變數 L4D2_SERVER_DIR 指定（資料夾內要有 srcds.exe）。

smoke：插件生命週期冒煙測試
    1. 不帶地圖開機（SourceMod 會在沒有地圖時就載入插件）
    2. 用 RCON 載入地圖 → 換圖 → reload 插件 → unload/load 插件
    判斷標準：SourceMod 錯誤 log 沒有 skills_mk2 的例外，插件狀態不是 Error/Failed。

skills：用 bot 跑技能測試（要搭配 src/scripting/skills_mk2/test/main_test.sp 編出來的測試版）
    插件內的測試腳本會把每個檢查點寫到 logs/skills_test.log，跑完寫 "== DONE ==" 後由這裡關服。

phase：只跑指定的測試腳本階段（在 c1m1_hotel，不做 reload、換圖、重開回合）
    例如 dissolve（淨化與 dissolve 槽的實驗，不在 skills 的完整流程裡）。

測試期間會暫時把 plugins/skills_mk2.smx 換成 --smx 指定的檔案，結束後一律還原。
"""
import argparse
import os
import re
import secrets
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rcon import Rcon  # noqa: E402

HOST = "127.0.0.1"
PORT = 27115  # 避開預設的 27015，伺服器只綁 127.0.0.1


class Server:
    def __init__(self, root, out):
        self.root = root
        self.game = os.path.join(root, "left4dead2")
        self.sm = os.path.join(self.game, "addons", "sourcemod")
        self.out = out
        self.password = secrets.token_hex(8)
        self.proc = None
        self.console_path = os.path.join(self.game, "console.log")
        self.console_start = os.path.getsize(self.console_path) if os.path.exists(self.console_path) else 0
        self.err_sizes = self._error_log_sizes()
        self.transcript = []

    # ---------- 記錄 ----------
    def log(self, msg):
        line = time.strftime("%H:%M:%S ") + msg
        print(line, flush=True)
        self.transcript.append(line)

    def _error_log_sizes(self):
        d = os.path.join(self.sm, "logs")
        return {f: os.path.getsize(os.path.join(d, f)) for f in os.listdir(d) if f.startswith("errors_")}

    def new_error_log_text(self):
        d = os.path.join(self.sm, "logs")
        text = []
        for f in sorted(os.listdir(d)):
            if not f.startswith("errors_"):
                continue
            p = os.path.join(d, f)
            start = self.err_sizes.get(f, 0)
            if os.path.getsize(p) > start:
                with open(p, "rb") as fh:
                    fh.seek(start)
                    text.append(fh.read().decode("utf-8", "replace"))
        return "".join(text)

    def console_text(self):
        if not os.path.exists(self.console_path):
            return ""
        with open(self.console_path, "rb") as fh:
            fh.seek(self.console_start)
            return fh.read().decode("utf-8", "replace")

    # ---------- 行程 ----------
    def start(self, map_name=None, extra=()):
        args = [os.path.join(self.root, "srcds.exe"), "-game", "left4dead2", "-console", "-condebug",
                "-port", str(PORT), "-maxplayers", "8", "-insecure", "-nomaster",
                "+ip", HOST, "+sv_lan", "1", "+rcon_password", self.password,
                ]
        args += list(extra)
        if map_name:
            args += ["+map", map_name]
        self.log("啟動 srcds（地圖：%s）" % (map_name or "無"))
        self.proc = subprocess.Popen(args, cwd=self.root, creationflags=subprocess.CREATE_NEW_CONSOLE)

    def stop(self, graceful=True):
        if not self.proc or self.proc.poll() is not None:
            return
        if graceful:
            try:
                self.rcon("quit", quiet=True)
            except Exception:
                pass
            try:
                self.proc.wait(30)
                self.log("srcds 已結束")
                return
            except subprocess.TimeoutExpired:
                pass
        self.log("強制結束 srcds")
        self.proc.kill()
        self.proc.wait(10)

    def rcon(self, command, quiet=False, retries=1, first_timeout=10.0):
        last = None
        for _ in range(retries):
            try:
                with Rcon(HOST, PORT, self.password) as r:
                    out = r.cmd(command, first_timeout=first_timeout)
                if not quiet:
                    self.log("> " + command)
                    for l in out.rstrip().splitlines():
                        self.log("  " + l)
                return out
            except Exception as e:  # 伺服器還沒好、換圖中
                last = e
                time.sleep(1)
        raise RuntimeError("RCON 失敗：%s（%s）" % (command, last))

    def wait_rcon(self, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if self.proc.poll() is not None:
                raise RuntimeError("srcds 意外結束")
            try:
                self.rcon("echo ping", quiet=True)
                return True
            except Exception:
                time.sleep(1)
        return False

    def wait_map(self, map_name, timeout=120):
        end = time.time() + timeout
        while time.time() < end:
            try:
                st = self.rcon("status", quiet=True, first_timeout=3.0)
                m = re.search(r"^map\s*:\s*(\S+)", st, re.M)
                if m and m.group(1) == map_name:
                    self.log("地圖 %s 已載入" % map_name)
                    return st
            except Exception:
                pass
            time.sleep(1)
        raise RuntimeError("等不到地圖 %s" % map_name)

    def wait_console(self, pattern, timeout):
        end = time.time() + timeout
        rx = re.compile(pattern)
        while time.time() < end:
            if rx.search(self.console_text()):
                return True
            if self.proc.poll() is not None:
                return False
            time.sleep(0.5)
        return False

    def save(self, name, text):
        with open(os.path.join(self.out, name), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)


def plugin_status(listing):
    """從 sm plugins list 的輸出找出 skills_mk2 那一行"""
    for l in listing.splitlines():
        if "KONOSUBA_SKILLS" in l or "skills_mk2" in l:
            return l.strip()
    return None


LOG_LINE = re.compile(r"^L (\d\d/\d\d/\d{4} - \d\d:\d\d:\d\d): (.*)$")


def parse_exceptions(text):
    """把 SourceMod 錯誤 log 裡的例外拆成 (時間, 訊息, 插件, [函式...])"""
    out = []
    cur = None
    for raw in text.splitlines():
        m = LOG_LINE.match(raw)
        if not m:
            continue
        ts, body = m.groups()
        if "[SM] Exception reported:" in body:
            cur = {"time": ts, "msg": body.split("Exception reported:", 1)[1].strip(), "plugin": "", "frames": []}
            out.append(cur)
        elif cur and "[SM] Blaming:" in body:
            cur["plugin"] = body.split("Blaming:", 1)[1].strip()
        elif cur and re.search(r"\[SM\]\s+\[\d+\]", body):
            fr = re.sub(r"^.*\[SM\]\s+\[\d+\]\s*", "", body)
            fm = re.search(r"::(\w+)$", fr)
            cur["frames"].append(fm.group(1) if fm else fr)
        elif cur and "Call stack trace" not in body:
            cur = None
    return out


def exception_signature(e):
    """跨版本比對用：訊息裡的 handle 位址、數字換掉，只留函式名稱"""
    msg = re.sub(r"[0-9a-f]{6,}", "X", e["msg"])
    msg = re.sub(r"\d+", "#", msg)
    return "%s | %s" % (msg, " < ".join(e["frames"]))


def check_errors(srv, results, strict=True):
    errs = srv.new_error_log_text()
    srv.save("errors_new.log", errs)
    srv.save("console.log", srv.console_text())
    # 只看 skills_mk2 的例外與載入失敗；其他插件（例如缺翻譯檔）原本就有錯誤
    mine = [e for e in parse_exceptions(errs) if e["plugin"] == "skills_mk2.smx"]
    srv.save("errors_summary.txt", "".join("%s %s\n" % (e["time"], exception_signature(e)) for e in mine))
    load_fail = re.findall(r'(?:Unable|Failed) to load plugin "skills_mk2\.smx".*', errs)
    if strict:
        results.append(("錯誤 log 沒有 skills_mk2 的例外", not mine, "%d 筆" % len(mine)))
    else:
        results.append(("skills_mk2 的例外（要跟基準版比對）", True, "%d 筆" % len(mine)))
    results.append(("沒有 skills_mk2 載入失敗", not load_fail, "; ".join(load_fail)))
    for e in mine:
        srv.log("例外：%s %s" % (e["time"], exception_signature(e)))


def run_smoke(srv, results):
    # ---- 第 1 段：不帶地圖開機 ----
    # 沒有地圖時 Metamod/SourceMod 還沒載入（RCON 下 sm 會是 Unknown command），
    # 要等第一張地圖開始載入才會載入插件，而且當下 worldspawn 還不存在。
    # 這正是 3e8a6d3 修的「開機無地圖時 OnPluginStart 建 entity 失敗」的情況。
    srv.start(None)
    if not srv.wait_rcon(120):
        raise RuntimeError("無地圖開機後 RCON 一直沒有回應")
    srv.rcon("map c1m1_hotel", first_timeout=3.0)
    st = srv.wait_map("c1m1_hotel")
    srv.save("status_c1m1.txt", st)
    time.sleep(8)
    text = srv.console_text()
    results.append(("開機後第一次載入：OnPluginStart 有執行", "=============Plugin Start===============" in text, ""))
    results.append(("開機後第一次載入：OnPluginStart 當下沒有地圖（有測到這個情況）",
                    "No map running, skip func_timescale creation" in text, ""))
    # ---- 第 2 段：地圖、換圖、reload ----
    st = plugin_status(srv.rcon("sm plugins list"))
    results.append(("載入地圖後插件狀態正常", bool(st) and not re.search(r"<(Error|Failed)>", st), st or "找不到"))
    srv.save("versions.txt", srv.rcon("meta version") + srv.rcon("sm version"))
    srv.rcon("changelevel c1m2_streets", first_timeout=3.0)
    srv.wait_map("c1m2_streets")
    time.sleep(8)
    srv.rcon("sm plugins reload skills_mk2")
    time.sleep(5)
    st = plugin_status(srv.rcon("sm plugins list"))
    results.append(("reload 後插件狀態正常", bool(st) and not re.search(r"<(Error|Failed)>", st), st or "找不到"))
    srv.rcon("sm plugins unload skills_mk2")
    time.sleep(2)
    srv.rcon("sm plugins load skills_mk2")
    time.sleep(5)
    st = plugin_status(srv.rcon("sm plugins list"))
    results.append(("unload/load 後插件狀態正常", bool(st) and not re.search(r"<(Error|Failed)>", st), st or "找不到"))
    srv.rcon("changelevel c1m1_hotel", first_timeout=3.0)
    srv.wait_map("c1m1_hotel")
    time.sleep(5)
    srv.stop()
    check_errors(srv, results)
    return results


def setup_bots(srv):
    """沒有真人時伺服器會休眠、也沒有 bot：開全 bot 模式、停掉 bot AI 與導演，再補到 4 個倖存者 bot。
    隱藏版爆裂會把所有倖存者炸倒，director_no_death_check 避免「全員倒地 → 任務失敗 → 回合重開」打亂測試。
    server.cfg 每次載入地圖都會把 sb_all_bot_game 設回 0，所以換圖後要再跑一次。"""
    for c in ("sb_all_bot_game 1", "sb_stop 1", "z_common_limit 0", "director_no_specials 1",
              "director_no_bosses 1", "director_no_mobs 1", "director_no_death_check 1"):
        srv.rcon("sm_cvar " + c, quiet=True)
    for _ in range(12):
        st = srv.rcon("status", quiet=True)
        n = len(re.findall(r'^#\s+\d+\s+"[^"]+"\s+BOT', st, re.M))
        if n >= 4:
            break
        srv.rcon("sb_add", quiet=True)
        time.sleep(1.5)
    time.sleep(3)
    srv.log("bot：\n" + srv.rcon("status", quiet=True))


def run_skills(srv, results, timeout, only=None):
    """only：只跑這些階段（phase 模式），不做 reload、換圖、重開回合。"""
    test_log = os.path.join(srv.sm, "logs", "skills_test.log")
    if os.path.exists(test_log):
        os.remove(test_log)

    def done_count(phase):
        if not os.path.exists(test_log):
            return 0
        with open(test_log, encoding="utf-8", errors="replace") as fh:
            return fh.read().count("== %s DONE ==" % phase)

    def phase(name, limit):
        before = done_count(name)
        srv.rcon("sm_skilltest " + name)
        end = time.time() + limit
        while time.time() < end:
            if done_count(name) > before:
                srv.log("階段 %s 完成" % name)
                return True
            if srv.proc.poll() is not None:
                raise RuntimeError("srcds 在階段 %s 意外結束" % name)
            time.sleep(1)
        raise RuntimeError("階段 %s 逾時" % name)

    try:
        srv.start("c1m1_hotel")
        srv.wait_map("c1m1_hotel")
        time.sleep(5)
        setup_bots(srv)
        if only:
            for name in only:
                phase(name, timeout)
            phase("finish", 30)
            results.append(("測試腳本跑完", True, ""))
            return results
        phase("main", timeout)
        phase("ex_down", 300)
        # reload：施放隱藏版爆裂中 reload 插件
        phase("ex_prep", 60)
        srv.rcon("sm plugins reload skills_mk2")
        time.sleep(3)
        phase("after_reload", 90)
        # 換圖：施放隱藏版爆裂中換圖
        phase("ex_prep", 60)
        # 全 bot 模式下換到戰役中間的地圖會被拉回第一張，所以換到另一個戰役的第一張
        srv.rcon("changelevel c2m1_highway", first_timeout=3.0)
        srv.wait_map("c2m1_highway")
        time.sleep(5)
        setup_bots(srv)
        phase("after_map", 90)
        # 投票重開回合：由測試腳本自己呼叫
        phase("ex_restart", 120)
        phase("finish", 30)
        results.append(("測試腳本跑完", True, ""))
    finally:
        srv.stop()
        if os.path.exists(test_log):
            shutil.copy(test_log, os.path.join(srv.out, "skills_test.log"))
            with open(test_log, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            fails = [l for l in text.splitlines() if " FAIL " in l]
            results.append(("測試腳本沒有 FAIL", not fails, "; ".join(fails)))
            os.remove(test_log)
        check_errors(srv, results, strict=False)
    return results


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["smoke", "skills", "phase"])
    ap.add_argument("--phase", action="append", default=[],
                    help="phase 模式要跑的測試腳本階段，可以給多次（例如 --phase ex_down --phase dissolve）")
    ap.add_argument("--smx", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--server", default=os.environ.get("L4D2_SERVER_DIR"))
    ap.add_argument("--timeout", type=float, default=900)
    a = ap.parse_args()
    if a.mode == "phase" and not a.phase:
        sys.exit("phase 模式要用 --phase 指定階段")
    if not a.server or not os.path.exists(os.path.join(a.server, "srcds.exe")):
        sys.exit("找不到 srcds.exe，請用 --server 或 L4D2_SERVER_DIR 指定伺服器資料夾")
    if b"srcds.exe" in subprocess.run(["tasklist", "/FI", "IMAGENAME eq srcds.exe"], capture_output=True).stdout:
        sys.exit("已經有 srcds.exe 在執行，先關掉再測")

    os.makedirs(a.out, exist_ok=True)
    srv = Server(a.server, a.out)
    target = os.path.join(srv.sm, "plugins", "skills_mk2.smx")
    backup = os.path.join(a.out, "skills_mk2.smx.server_backup")
    shutil.copy2(target, backup)
    shutil.copy2(a.smx, target)
    srv.log("已暫時換上 %s（原檔備份在 %s）" % (a.smx, backup))
    results = []
    try:
        if a.mode == "smoke":
            run_smoke(srv, results)
        else:
            run_skills(srv, results, a.timeout, a.phase if a.mode == "phase" else None)
    except Exception as e:
        results.append(("測試流程沒有中斷", False, str(e)))
        if a.mode == "smoke":
            try:
                srv.stop()
                check_errors(srv, results)
            except Exception:
                pass
    finally:
        srv.stop()
        shutil.copy2(backup, target)
        srv.log("已還原伺服器原本的 skills_mk2.smx")
        srv.save("transcript.txt", "\n".join(srv.transcript) + "\n")

    print()
    allok = True
    for name, ok, detail in results:
        allok &= ok
        print("[%s] %s %s" % ("PASS" if ok else "FAIL", name, ("— " + detail) if detail else ""))
    print("\n結果：%s（輸出在 %s）" % ("全部通過" if allok else "有失敗", a.out))
    sys.exit(0 if allok else 1)


if __name__ == "__main__":
    main()
