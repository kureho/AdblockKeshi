#!/usr/bin/env python3
"""
scripts/review/auto_judge.py — 報告の週 1 回判定を Claude が自動で行い、関門を通ったものだけ main に載せる

launchd（毎週月曜 06:30・scripts/review/weekly_review.sh）が build_review_packet.py の後に呼ぶ。

  1. .review-packets/status.json を読み、今日作った束に未判定（または止まっている候補）が無ければ何もしない
     ＝Claude を起動しない（利用枠を使わない）
  2. 作業用の worktree（.review-packets/.auto-wt・origin/main と同じ中身）で `claude -p` を起動し、
     scripts/review/auto-judge-prompt.md の指示で review/results/ と review/rules/ の新しいファイルだけ書かせる
     （Claude は commit・push しない。使える道具は allowed_tools() のものだけ）
  3. 関門（Claude ではなくこのスクリプトが確かめる）:
     - 変わったのが review/results/・review/rules/ の新しいファイルだけ
     - 結果に束の未判定の report_id が全部あり、outcome が 5 値のどれか・note に URL が無い
     - applied があるなら規則のファイルがあり、規則のファイルがあるなら applied がある
     - 規則が配信と同じ検査（check_manual_rules.ts）を通る
     - 規則ごとに、報告されたページを「今の規則」と「今の規則＋新しい規則」で計測し、
       開けなくならない・文字数と画像数が 8 割を切らない
     - D1 に流す予定の UPDATE を dry-run で出せる
  4. 全部通れば worktree で commit して origin/main に push（apply-review-results.yml と
     weekly-cdn-sync.yml が動く）。1 つでも外れたら載せずに「保留」として残す
     （worktree はそのまま＝人が開いて続きを決める。次の週も保留が残っている間は新しく判定しない）

結果は .review-packets/auto-judge-status.json（朝のレポートが読む）とログに残す。
★このリポジトリは公開。報告の URL・画面は .review-packets/（.gitignore 済み）の外に書かない。

使い方:
  python3 -B scripts/review/auto_judge.py            # 本番（launchd から）
  python3 -B scripts/review/auto_judge.py --no-push  # 関門まで通して push だけしない（試し）
  python3 -B scripts/review/auto_judge.py --gate-only # Claude を起動せず、worktree の今の中身で関門だけ通す
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# SRC = このスクリプトがあるチェックアウト（launchd からは origin/main と同じ .review-packets/.tools-wt）。
#       プロンプト・関門の検査・計測ツールのソースはここの版を使う（手元の作業ブランチに左右されない）
# REPO = 本体のチェックアウト（束・node_modules・git の置き場）
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"  # launchd の最小の環境でも npx・swiftc・git を見つける
SRC = Path(__file__).resolve().parents[2]
REPO = Path(subprocess.run(["git", "-C", str(SRC), "rev-parse", "--path-format=absolute", "--git-common-dir"],
                           capture_output=True, text=True, check=True).stdout.strip()).parent
PACKETS = REPO / ".review-packets"
STATUS_IN = PACKETS / "status.json"
STATUS_OUT = PACKETS / "auto-judge-status.json"
WT = PACKETS / ".auto-wt"
RULES_DIR = PACKETS / ".rules"
BIN = PACKETS / ".bin" / "measure-gate"  # 束づくりの measure とは別（SRC の版から作る）
LOCK = PACKETS / ".auto-judge.lock"
CLAUDE = "/opt/homebrew/bin/claude"
MODEL = "claude-opus-5-5"
CLAUDE_TIMEOUT_SEC = 45 * 60
OUTCOMES = {"applied", "in_app_ad", "site_own_ad", "not_reproduced", "invalid"}
URL_LIKE = re.compile(r"https?://|www\.|\b[a-z0-9-]+\.[a-z]{2,}/", re.I)
CURRENT_RULES = ["merged-rules.json", "popunder-rules.json", "rules-reported.json", "security-rules.json"]


class Hold(Exception):
    """関門で止めた（載せない・人の確認に回す）"""


def now() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")


def log(msg: str) -> None:
    print(f"[{dt.datetime.now():%Y-%m-%d %H:%M:%S}] {msg}", flush=True)


def write_status(state: str, **kw) -> None:
    STATUS_OUT.write_text(json.dumps({"run_at": now(), "state": state, **kw}, ensure_ascii=False, indent=2) + "\n")
    log(f"状態: {state} {kw.get('reason', '')}")


def run(cmd: list[str], *, cwd: Path | None = None, timeout: int = 600, check: bool = True) -> subprocess.CompletedProcess:
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    if check and p.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd[:3])} が失敗（exit {p.returncode}）: {(p.stderr or p.stdout)[-600:]}")
    return p


# ---------- worktree ----------

def wt_dirty() -> list[str]:
    p = run(["git", "-C", str(WT), "status", "--porcelain", "--untracked-files=all"])
    return [l for l in p.stdout.splitlines() if l.strip()]


def prepare_worktree(base: str = "origin/main") -> None:
    run(["git", "-C", str(REPO), "fetch", "-q", "origin", "main"], timeout=120)
    if not (WT / ".git").exists():
        run(["git", "-C", str(REPO), "worktree", "add", "-q", "--detach", str(WT), base], timeout=120)
    else:
        run(["git", "-C", str(WT), "checkout", "-q", "--detach", base], timeout=120)


# ---------- Claude ----------

def build_prompt(packet: Path, date: str, scratch: Path) -> str:
    tpl = (SRC / "scripts/review/auto-judge-prompt.md").read_text()
    return (tpl.replace("{PACKET}", str(packet)).replace("{DATE}", date).replace("{BIN}", str(BIN))
            .replace("{RULES}", str(RULES_DIR)).replace("{SCRATCH}", str(scratch)).replace("{FETCH}", str(FETCH)))


# 報告されたページは外の人が作った物＝中の文で Claude が操られても被害が出ないよう、道具を絞る
# - 書けるのは review/results・review/rules と、その回の作業場所（束の auto-scratch）だけ。
#   計測ツール・今の規則・束の中身・git の中・このスクリプトのある場所には書けない（関門の材料を守る）
# - 読めるのは作業用 worktree・その回の束・今の規則だけ（--add-dir。読む道具はその中なら許可なしで動く）
# - コマンドは計測ツールと fetch_page.py（保存先が作業場所に固定）だけ。curl・ls・git などは渡さない
FETCH = SRC / "scripts/review/fetch_page.py"


def allowed_tools(scratch: Path) -> list[str]:
    return [
        "Write(review/results/**)", "Write(review/rules/**)",
        "Edit(review/results/**)", "Edit(review/rules/**)",
        f"Write(/{scratch}/**)", f"Edit(/{scratch}/**)",
        f"Bash({BIN} run:*)", f"Bash({BIN} shoot:*)",
        f"Bash(/opt/homebrew/bin/python3 -I {FETCH}:*)",
    ]


# 個人の Max（~/.claude の claude.ai ログイン）だけで動かす。API キーやほかの席のトークンが環境にあると
# そちらが優先されて従量の請求になり得るので外す
AUTH_ENV = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CONFIG_DIR",
            "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"]


def claude_env() -> dict:
    env = {k: v for k, v in os.environ.items() if k not in AUTH_ENV}
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    return env


def check_claude_login() -> None:
    p = subprocess.run([CLAUDE, "auth", "status"], capture_output=True, text=True, timeout=60, env=claude_env())
    try:
        a = json.loads(p.stdout)
    except json.JSONDecodeError:
        a = {}
    if not (a.get("loggedIn") and a.get("authMethod") == "claude.ai" and a.get("subscriptionType") == "max"
            and a.get("apiProvider") == "firstParty"):
        raise RuntimeError("個人の Max で Claude にログインしていない（API の従量にならないよう起動しない）")


def run_claude(packet: Path, date: str) -> dict:
    check_claude_login()
    ensure_measure_binary()
    scratch = packet / "auto-scratch"
    scratch.mkdir(exist_ok=True)
    cmd = [CLAUDE, "-p", build_prompt(packet, date, scratch),
           "--model", MODEL, "--permission-mode", "default",
           "--allowedTools", *allowed_tools(scratch),
           "--add-dir", str(packet), str(RULES_DIR),
           "--output-format", "json", "--no-session-persistence"]
    env = claude_env()
    env["AUTO_JUDGE_SCRATCH"] = str(scratch)
    # 関門の材料（計測ツール・今の規則・束の計測ページと下書き）は Claude の前後で同じであること
    # （計測ツールの --out は場所を選べるので、書き換えられていないかを中身で確かめる）
    guarded = [BIN, *sorted(RULES_DIR.glob("*.json")), packet / "sites.txt", packet / "results-draft.json"]
    before_hash = {g: _sha256(g) for g in guarded if g.exists()}
    log(f"Claude を起動（{MODEL}・最大 {CLAUDE_TIMEOUT_SEC // 60} 分）")
    p = subprocess.run(cmd, cwd=WT, capture_output=True, text=True, timeout=CLAUDE_TIMEOUT_SEC, env=env)
    (packet / "auto-judge-output.json").write_text(p.stdout)
    if p.stderr.strip():
        (packet / "auto-judge-stderr.txt").write_text(p.stderr)
    try:
        out = json.loads(p.stdout)
    except json.JSONDecodeError:
        out = {}
    changed = [g.name for g, h in before_hash.items() if not g.exists() or _sha256(g) != h]
    if changed:
        raise Hold(f"Claude の実行中に関門の材料が変わった: {', '.join(changed)}")
    if p.returncode != 0 or out.get("is_error"):
        raise Hold(f"Claude の実行が失敗（exit {p.returncode}）")
    return out


def _sha256(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------- 関門 ----------

def changed_files() -> tuple[list[str], list[str]]:
    results, rules = [], []
    for line in wt_dirty():
        status, path = line[:2], line[3:]
        if status != "??":
            raise Hold(f"既存のファイルが変わった: {path}")
        if re.fullmatch(r"review/results/[\w.-]+\.json", path):
            results.append(path)
        elif re.fullmatch(r"review/rules/[\w.-]+\.json", path):
            rules.append(path)
        else:
            raise Hold(f"書いてよい場所の外にファイルがある: {path}")
    return results, rules


def check_results(results: list[str], packet: Path) -> dict:
    if len(results) != 1:
        raise Hold(f"結果のファイルが {len(results)} 本（1 本のはず）")
    data = json.loads((WT / results[0]).read_text())
    draft = json.loads((packet / "results-draft.json").read_text())
    want = {r["report_id"] for r in draft.get("results", [])}
    got = {r.get("report_id"): r for r in data.get("results", [])}
    if want - set(got):
        raise Hold(f"判定していない報告が {len(want - set(got))} 件")
    if set(got) - want:
        raise Hold("束に無い報告を判定している")
    for r in got.values():
        if r.get("outcome") not in OUTCOMES:
            raise Hold(f"outcome が 5 値の外: {r.get('outcome')!r}")
        if URL_LIKE.search(str(r.get("note", ""))):
            raise Hold("note に URL らしいものがある（公開リポジトリ）")
    for c in data.get("candidates", []) or []:
        if c.get("decision") != "closed":
            raise Hold("候補の decision が closed 以外")
    return data


def check_rules_format() -> None:
    p = run(["npx", "tsx", str(SRC / "scripts/review/check_manual_rules.ts"), str(WT / "review/rules")],
            cwd=REPO / "workers", timeout=300, check=False)
    if p.returncode != 0:
        msg = next((l for l in (p.stderr or p.stdout).splitlines() if "Error" in l), "形が外れている")
        raise Hold(f"規則が配信の検査を通らない: {msg.strip()[:200]}")


def _domains(rule_file: Path) -> set[str]:
    doms: set[str] = set()
    for r in json.loads(rule_file.read_text()).get("rules", []):
        for d in r.get("trigger", {}).get("if-domain", []):
            doms.add(d.lstrip("*").lower())
    return doms


def _host(url: str) -> str:
    m = re.match(r"^[a-z]+://([^/:?#]+)", url.strip(), re.I)
    return m.group(1).lower() if m else ""


def ensure_measure_binary() -> None:
    """計測ツールがソースより古い・無いときだけビルドする（build_review_packet.py と同じ作り方）。"""
    src = SRC / "scripts/measure/measure.swift"
    if not BIN.exists() or BIN.stat().st_mtime < src.stat().st_mtime:
        BIN.parent.mkdir(parents=True, exist_ok=True)
        run(["swiftc", "-O", str(src), "-o", str(BIN), "-framework", "WebKit", "-framework", "AppKit"], timeout=600)


def _measure(sites: Path, rules: list[Path], out: Path, repeat: int = 1) -> list[dict]:
    for attempt in range(2):
        run([str(BIN), "run", "--config", out.stem, "--rules", ",".join(str(r) for r in rules),
             "--sites", str(sites), "--out", str(out), "--wait", "10", "--repeat", str(repeat), "--concurrency", "1"],
            timeout=900)
        res = json.loads(out.read_text())["results"]
        if all(r.get("textLen", -1) >= 0 and not r.get("failed") for r in res):
            return res
    return res


def _block_filters(rule_file: Path) -> list[re.Pattern]:
    out = []
    for r in json.loads(rule_file.read_text()).get("rules", []):
        if r.get("action", {}).get("type") != "block":
            continue
        t = r.get("trigger", {})
        try:
            out.append(re.compile(t["url-filter"], 0 if t.get("url-filter-is-case-sensitive") else re.I))
        except (KeyError, re.error) as e:
            raise Hold(f"{rule_file.name}: url-filter を読めない（{e}）")
    return out


def _hits(results: list[dict], filters: list[re.Pattern]) -> int:
    return sum(1 for r in results for u in r.get("urls", []) if any(p.search(u) for p in filters))


def check_rules_measure(rules: list[str], packet: Path, scratch: Path) -> list[str]:
    sites_all = [s.strip() for s in (packet / "sites.txt").read_text().splitlines() if s.strip()] \
        if (packet / "sites.txt").exists() else []
    current = [RULES_DIR / n for n in CURRENT_RULES]
    lines: list[str] = []
    if rules:
        ensure_measure_binary()
    for rel in rules:
        f = WT / rel
        doms = _domains(f)
        sites = [s for s in sites_all if any(_host(s) == d or _host(s).endswith("." + d) for d in doms)]
        if not sites:
            raise Hold(f"{rel}: 規則のサイトが束の計測ページに無い")
        sites_file = scratch / f"gate-sites-{f.stem}.txt"
        sites_file.write_text("\n".join(sites) + "\n")
        only = scratch / f"gate-{f.stem}.rules.json"
        only.write_text(json.dumps(json.loads(f.read_text())["rules"]))
        # 今の規則 と 今の規則＋新しい規則 で 2 回ずつ開いて比べる
        # （広告は読み込むたびに入れ替わるので 2 回ずつ・通信先の名前ではなく URL の形で数える）
        before = _measure(sites_file, current, scratch / f"gate-before-{f.stem}.json", repeat=2)
        after = _measure(sites_file, current + [only], scratch / f"gate-after-{f.stem}.json", repeat=2)
        # 効き目: 規則の url-filter に当たる通信が、今の規則では通っていて、新しい規則でほぼ消えること
        filters = _block_filters(f)
        if filters:
            hit_b, hit_a = _hits(before, filters), _hits(after, filters)
            if hit_b == 0:
                raise Hold(f"{rel}: 規則に当たる通信が今の規則のページに 1 つも無い（もう止まっているか、何も止めていない）")
            if hit_a * 2 > hit_b:
                raise Hold(f"{rel}: 規則を入れても当たる通信が残る（{hit_b}→{hit_a}）")
            lines.append(f"{rel}: 規則に当たる通信 今の規則 {hit_b} 件→新しい規則あり {hit_a} 件（2 回ずつ）")
        else:
            lines.append(f"{rel}: 見た目を隠す規則だけなので効き目は計測していない（壊れだけ確かめた）")
        # 壊れ: サイトごとに 2 回のうち良い方どうしで比べる（読み込みのぶれで止めすぎない）
        for site in dict.fromkeys(r["site"] for r in before):
            bs = [r for r in before if r["site"] == site]
            as_ = [r for r in after if r["site"] == site and not r.get("failed") and r.get("textLen", -1) >= 0]
            if not as_:
                raise Hold(f"{rel}: 規則を足すとページが開けない")
            best = lambda rs, k: max(r.get(k, -1) for r in rs)
            for key, label in (("textLen", "文字数"), ("imgCount", "画像数"), ("imgLoaded", "表示できる画像")):
                bv, av = best(bs, key), best(as_, key)
                if bv > 0 and av < bv * 0.8:
                    raise Hold(f"{rel}: 規則を足すと{label}が {bv}→{av} に減る")
            lines.append(f"{rel}: 文字 {best(bs, 'textLen')}→{best(as_, 'textLen')}・"
                         f"表示できる画像 {best(bs, 'imgLoaded')}→{best(as_, 'imgLoaded')}")
    return lines


def check_dry_run(result_rel: str) -> int:
    p = run(["npx", "tsx", str(SRC / "scripts/review/run-apply-review-results.ts"),
             "--dir", str(WT / "review/results"), "--dry-run"], cwd=REPO / "workers", timeout=300)
    out = json.loads(p.stdout[p.stdout.find("{"):])
    name = Path(result_rel).name
    mine = [r for r in out.get("results", []) if r.get("fileName") == name]
    if not out.get("ok") or not mine or not mine[0].get("ok"):
        raise Hold("D1 に流す予定の UPDATE を作れない（dry-run が失敗）")
    return int(mine[0].get("updated", 0))


def gate(packet: Path) -> dict:
    scratch = packet / "auto-scratch"
    scratch.mkdir(exist_ok=True)
    results, rules = changed_files()
    data = check_results(results, packet)
    applied = sum(1 for r in data["results"] if r["outcome"] == "applied")
    if applied and not rules:
        raise Hold("applied があるのに規則のファイルが無い")
    if rules and not applied:
        raise Hold("規則のファイルがあるのに applied が無い")
    check_rules_format()
    measured = check_rules_measure(rules, packet, scratch)
    updated = check_dry_run(results[0])
    return {"results_file": results[0], "rule_files": rules, "applied": applied,
            "judged": len(data["results"]), "dry_run_updates": updated, "measured": measured}


def commit_and_push(info: dict, push: bool) -> str | None:
    files = [info["results_file"], *info["rule_files"]]
    g = ["git", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=", "-C", str(WT)]  # フックは動かさない
    run([*g, "add", "--", *files])
    sites = ", ".join(Path(r).stem.split("-", 3)[-1] for r in info["rule_files"]) or "規則なし"
    msg = (f"auto-judge: 報告 {info['judged']} 件の判定結果（{sites}）\n\n"
           "scripts/review/auto_judge.py の関門（場所・形式・計測・dry-run）を通ったもの。\n\n"
           "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")
    run([*g, "commit", "-q", "--no-verify", "-m", msg])
    sha = run(["git", "-C", str(WT), "rev-parse", "--short", "HEAD"]).stdout.strip()
    if push:
        p = run([*g, "push", "-q", "--no-verify", "origin", "HEAD:main"], timeout=120, check=False)
        if p.returncode != 0:  # 同じ時間に自動同期が main に載せた時など。足すのは新しいファイルだけなので重ねて 1 回だけ再送
            run([*g, "pull", "-q", "--rebase", "origin", "main"], timeout=120)
            run([*g, "push", "-q", "--no-verify", "origin", "HEAD:main"], timeout=120)
            sha = run(["git", "-C", str(WT), "rev-parse", "--short", "HEAD"]).stdout.strip()
        return sha
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-push", action="store_true")
    ap.add_argument("--gate-only", action="store_true")
    ap.add_argument("--base", default="origin/main", help="試しのときだけ: worktree の元にするコミット")
    ap.add_argument("--any-date", action="store_true", help="試しのときだけ: 今日以外の束でも動かす")
    args = ap.parse_args()

    lock_fd = open(LOCK, "a")  # ファイルは残したまま OS のロックだけ使う（二重起動を防ぐ）
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("ほかの自動判定が動いているので何もしない")
        return 0
    st: dict = {}
    reply = ""
    try:
        st = json.loads(STATUS_IN.read_text())
        packet = Path(st["packet"]).parent
        date = packet.name
        if not args.gate_only:
            if date != dt.date.today().isoformat() and not args.any_date:
                write_status("failed", packet=str(packet), reason="今日の束が無い（束の作成が失敗した可能性）")
                return 1
            if not st.get("pending_reports") and not st.get("stalled_candidates"):
                write_status("skipped", packet=str(packet), reason="未判定 0 件（Claude は起動していない）")
                return 0
            if (WT / ".git").exists() and wt_dirty():
                write_status("held", packet=str(packet), worktree=str(WT),
                             reason="前回の保留が残っている（人が片付けるまで新しく判定しない）")
                return 0
            prepare_worktree(args.base)
            out = run_claude(packet, date)
            reply = str(out.get("result", ""))[:2000]
            log(f"Claude の返事: {reply}")
        info = gate(packet)
        sha = commit_and_push(info, push=not args.no_push and args.base == "origin/main")
        write_status("pushed" if sha else "passed-not-pushed", packet=str(packet), commit=sha, claude_reply=reply, **info)
        return 0
    except Hold as e:
        write_status("held", packet=str(st.get("packet", "")), worktree=str(WT), reason=str(e), claude_reply=reply)
        return 0
    except Exception as e:  # noqa: BLE001
        write_status("failed", reason=f"{type(e).__name__}: {e}"[:600], worktree=str(WT))
        return 1
    finally:
        fcntl.flock(lock_fd, fcntl.LOCK_UN)
        lock_fd.close()


if __name__ == "__main__":
    sys.exit(main())
