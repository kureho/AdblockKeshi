#!/usr/bin/env python3
"""
scripts/review/build_review_packet.py — A-88 §2「報告の週 1 回判定」の下ごしらえ

Claude なしで毎週自動で走り（launchd・Mac 上）、判定用の束を手元に作る:
  1. 本番 D1 から未判定の報告（reports.review_outcome IS NULL）と、止まっているルール候補
     （rule_candidates.status = 'kureho_queue'）を**読み取りのみ**で取る
  2. Safari で見た報告は、報告されたページを計測ツール（scripts/measure/measure.swift＝iOS Safari と
     同じ規則エンジン）で「今配信中の規則」のまま開き、残っている通信先と画面を集める
  3. .review-packets/YYYY-MM-DD/ に packet.md（判定用）・results-draft.json（結果の下書き）・
     shots/（画面）を書き、.review-packets/status.json に件数を残す

判定そのものは次に開いたセッションで Claude が行い、結果を review/results/ に書く
（書き方は review/results/README.md）。D1 への書き込みはこのスクリプトでは一切しない。

★このリポジトリは公開。報告の URL・メモ・画面は .review-packets/（.gitignore 済み）にだけ置く。

使い方:
  python3 scripts/review/build_review_packet.py              # 束を作る（週 1 回の本番）
  python3 scripts/review/build_review_packet.py --count-only # 未判定の件数だけ表示（朝のレポート用）
  python3 scripts/review/build_review_packet.py --no-measure # D1 だけ読んで束を作る（計測を省く）
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit

REPO = Path(__file__).resolve().parents[2]
WORKERS = REPO / "workers"
PACKETS_ROOT = REPO / ".review-packets"
D1_DATABASE = "adblockkeshi-reports"
JST = dt.timezone(dt.timedelta(hours=9))

# launchd から呼ばれても npx / swiftc / git が見つかるようにする
TOOL_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

# 今配信中の規則（4.3.0 の既定＝基本保護 merged ＋ 2 本目 popunder ＋ 報告由来）。
# security-rules は「利用者の既定」には入っていない（merged のセキュリティ枠は 0 件）が、
# 報告された見知らぬページを開くときの Mac 側の防護として足す。広告の漏れの判定にはほぼ影響しない。
CDN_RULE_FILES = (
    "docs/cdn/merged-rules.json",
    "docs/cdn/popunder-rules.json",
    "docs/cdn/rules-reported.json",
    "docs/cdn/security-rules.json",
)

REPORT_QUERY = (
    "SELECT id, domain, url, memo, seen_in, report_kind, ad_type, status, created_at, app_version "
    "FROM reports WHERE review_outcome IS NULL ORDER BY created_at ASC LIMIT 200"
)
CANDIDATE_QUERY = (
    "SELECT id, domain, status, rule_text, unique_uuid_count, unique_ip_count, last_reported_at "
    "FROM rule_candidates WHERE status = 'kureho_queue' ORDER BY last_reported_at ASC LIMIT 200"
)
COUNT_QUERY = "SELECT COUNT(*) AS n FROM reports WHERE review_outcome IS NULL"

PACKET_DIR_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


# ---------------------------------------------------------------------------
# 純粋な関数（scripts/tests/test_build_review_packet.py で固定）
# ---------------------------------------------------------------------------

def page_url_for_measure(url: str | None) -> str | None:
    """報告された URL を計測ツールで開いてよい形にする。

    クエリとフラグメントは外す（利用者のトークン・メールアドレス等が入りうる＝本人の代わりに
    そのページを開くことになる。広告の出方はほぼパスで決まる）。https 以外・ホスト無しは開かない。
    旧版・集計済みの報告は「ホスト/パス」の形（スキーム無し）で保存されているので https として開く。
    """
    if not url or " " in url.strip():
        return None
    url = url.strip()
    if "://" not in url:
        url = "https://" + url
    try:
        parts = urlsplit(url)
        host = parts.hostname
    except ValueError:
        return None
    if parts.scheme != "https" or not host or "." not in host:
        return None
    return urlunsplit((parts.scheme, parts.netloc, parts.path or "/", "", ""))


def _site_root(domain: str) -> str:
    d = (domain or "").lower().strip(".")
    return d[4:] if d.startswith("www.") else d


def _is_same_or_sub(host: str, domain: str) -> bool:
    return host == domain or host.endswith("." + domain)


def third_party_hosts(hosts, site_domain: str) -> list[str]:
    """報告サイト自身（とそのサブドメイン）以外の通信先。"""
    root = _site_root(site_domain)
    return sorted({h.lower() for h in hosts if h and not _is_same_or_sub(h.lower(), root)})


def ad_marked_hosts(hosts, ad_domains: set[str]) -> list[str]:
    """既知の広告網（ホスト自身か親ドメインが ad_domains にある）に当たる通信先。"""
    out = set()
    for h in hosts:
        labels = h.lower().split(".")
        if any(".".join(labels[i:]) in ad_domains for i in range(len(labels) - 1)):
            out.add(h.lower())
    return sorted(out)


def suggest_outcome(row: dict) -> str | None:
    """機械的に決まる結果だけ下書きする。Safari の報告は人（Claude）が画面と通信先を見て決める。"""
    if row.get("seen_in") == "other_app":
        # Safari のコンテンツブロッカーはほかのアプリの中の広告には効かない
        return "in_app_ad"
    return None


def results_draft(rows: list[dict], reviewed_at: str) -> dict:
    """review/results/<日付>.json の下書き。報告 ID と結果だけを持つ（URL・メモは入れない）。"""
    return {
        "reviewed_at": reviewed_at,
        "results": [{"report_id": r["id"], "outcome": suggest_outcome(r) or ""} for r in rows],
    }


def _fmt_ts(ts) -> str:
    try:
        return dt.datetime.fromtimestamp(int(ts), JST).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError, OSError):
        return "?"


def render_packet(date: str, rows: list[dict], measurements: dict, candidates: list[dict]) -> str:
    lines = [
        f"# 広告消し 報告の判定用の束（{date}）",
        "",
        "★この束は手元専用。報告された URL・メモ・画面を含むので**公開リポジトリに入れない**"
        "（.review-packets/ は .gitignore 済み）。",
        "",
        f"- 未判定 {len(rows)} 件（reports.review_outcome が空のもの）",
        f"- 止まっているルール候補 {len(candidates)} 件（rule_candidates.status = kureho_queue）",
        "- 結果の書き方: review/results/README.md。下書きは同じフォルダの results-draft.json"
        "（outcome が空の行を埋めてから review/results/<日付>.json に写す）",
        "- 画面と通信先は「今配信中の規則」（merged + popunder + 報告由来 + 防護用の security）で開いたもの。"
        "URL のクエリは外して開いている",
        "",
    ]
    if not rows and not candidates:
        lines += ["判定するものはありません。", ""]
        return "\n".join(lines)

    for i, r in enumerate(rows, 1):
        suggestion = suggest_outcome(r)
        lines += [
            f"## {i}. {r.get('domain') or '(ドメイン無し)'}",
            "",
            f"- report_id: `{r['id']}`",
            f"- 受付: {_fmt_ts(r.get('created_at'))} JST / 状態: {r.get('status')} / "
            f"見た場所: {r.get('seen_in') or '不明'} / 種類: {r.get('report_kind') or '不明'} / "
            f"広告の形: {r.get('ad_type') or '不明'} / アプリ: {r.get('app_version') or '不明'}",
            f"- 報告 URL: {r.get('url') or '(無し)'}",
            f"- メモ: {r.get('memo') or '(無し)'}",
        ]
        if suggestion:
            lines.append(f"- 下書きの結果: **{suggestion}**（機械的に決まる）")
        m = measurements.get(r["id"])
        if m:
            if m.get("failed"):
                lines.append(f"- 計測: 開けなかった（{m.get('fail_reason') or '理由不明'}）")
            lines.append(f"- 開いた URL: {m.get('opened_url')}")
            if m.get("shot"):
                lines.append(f"- 画面: {m['shot']}")
            marked = m.get("ad_marked") or []
            lines.append(f"- 広告規則の全体（blockerList 15 万件）に載っているドメインの通信先（条件つきの規則を含む）（{len(marked)}）: " + (", ".join(marked) if marked else "なし"))
            others = [h for h in (m.get("third_party") or []) if h not in marked]
            lines.append(f"- そのほかの外部の通信先（{len(others)}）: " + (", ".join(others) if others else "なし"))
        elif not suggestion:
            lines.append("- 計測: なし（Safari の https URL ではない、または計測を省いた）")
        lines.append("")

    if candidates:
        lines += ["## 止まっているルール候補（kureho_queue）", ""]
        for c in candidates:
            lines += [
                f"- `{c['id']}` {c.get('domain')} / {c.get('status')} / 報告者 {c.get('unique_uuid_count')} 人・"
                f"回線 {c.get('unique_ip_count')} / 最終報告 {_fmt_ts(c.get('last_reported_at'))} JST",
                f"  - rule_text: `{c.get('rule_text')}`",
            ]
        lines.append("")
    return "\n".join(lines)


def packets_to_prune(root: Path, keep: int) -> list[Path]:
    """日付名（YYYY-MM-DD）の束フォルダのうち、新しい keep 個を残して古いものを返す。"""
    dirs = sorted(p for p in root.iterdir() if p.is_dir() and PACKET_DIR_RE.match(p.name))
    return dirs[:-keep] if len(dirs) > keep else []


# ---------------------------------------------------------------------------
# 入出力（D1 読み取り・計測ツール・書き出し）
# ---------------------------------------------------------------------------

def _env() -> dict:
    env = dict(os.environ)
    env["PATH"] = TOOL_PATH + ":" + env.get("PATH", "")
    return env


def d1_select(sql: str) -> list[dict]:
    """wrangler（この Mac のログイン）で本番 D1 に SELECT を 1 本流す。書き込みはしない。"""
    if not sql.lstrip().upper().startswith("SELECT"):
        raise ValueError("読み取り（SELECT）以外は流さない")
    proc = subprocess.run(
        ["npx", "wrangler", "d1", "execute", D1_DATABASE, "--remote", "--json", "--command", sql],
        cwd=WORKERS, env=_env(), capture_output=True, text=True, timeout=120,
    )
    if proc.returncode != 0:
        raise RuntimeError(f"wrangler d1 execute が失敗（exit {proc.returncode}）: {proc.stderr.strip()[-300:]}")
    data = json.loads(proc.stdout)
    return data[0]["results"] if data else []


def fetch_cdn_rules(dest: Path) -> list[str]:
    """公開中（origin/main）の配信ファイルを dest に書き出す。作業ツリーには触らない。空の規則は除く。"""
    subprocess.run(["git", "fetch", "--quiet", "origin", "main"], cwd=REPO, env=_env(),
                   capture_output=True, timeout=120)
    dest.mkdir(parents=True, exist_ok=True)
    paths = []
    for rel in CDN_RULE_FILES:
        proc = subprocess.run(["git", "show", f"origin/main:{rel}"], cwd=REPO, env=_env(),
                              capture_output=True, timeout=120)
        if proc.returncode != 0:
            continue
        try:
            if not json.loads(proc.stdout):
                continue  # 0 件の規則は WebKit に渡さない
        except json.JSONDecodeError:
            continue
        out = dest / Path(rel).name
        out.write_bytes(proc.stdout)
        paths.append(str(out))
    return paths


def ad_domains_from(dest: Path) -> set[str]:
    """漏れの目印に使うドメイン集合。公開中の広告規則の全体（blockerList.json・15 万件）から
    「サイト全体を止める」形のドメインを抜く。

    ★merged（今 WebKit に渡している 13 万件）から作らない: 漏れているのは merged が上限で捨てた側なので、
    merged 由来の集合では漏れが 1 件も目印にならない（9/27 初回実行で doubleclick が目印 0 件だった）。
    15 万件にも入らない末尾（googlesyndication.com 等）はここでも拾えない＝目印は下限。
    """
    proc = subprocess.run(["git", "show", "origin/main:docs/cdn/blockerList.json"], cwd=REPO, env=_env(),
                          capture_output=True, timeout=120)
    if proc.returncode != 0:
        return set()
    dest.mkdir(parents=True, exist_ok=True)
    full = dest / "blockerList.json"
    full.write_bytes(proc.stdout)
    out = dest / "ad-domains.txt"
    proc = subprocess.run([sys.executable, str(REPO / "scripts/measure/extract-block-domains.py"), str(full), str(out)],
                          capture_output=True, text=True, timeout=300)
    if proc.returncode != 0 or not out.exists():
        return set()
    return {line.strip() for line in out.read_text().splitlines() if line.strip()}


def measure_binary(cache: Path) -> Path:
    """計測ツールを必要なときだけビルドする（ソースより古い・無いとき）。"""
    src = REPO / "scripts/measure/measure.swift"
    binary = cache / "measure"
    if not binary.exists() or binary.stat().st_mtime < src.stat().st_mtime:
        cache.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", str(src), "-o", str(binary), "-framework", "WebKit", "-framework", "AppKit"],
                       env=_env(), check=True, capture_output=True, timeout=600)
    return binary


def measure_reports(rows: list[dict], packet: Path, rule_paths: list[str], ad_domains: set[str],
                    binary: Path, max_pages: int) -> dict:
    targets = []
    for r in rows:
        if r.get("seen_in") == "other_app":
            continue
        opened = page_url_for_measure(r.get("url"))
        if opened:
            targets.append((r, opened))
    targets = targets[:max_pages]
    if not targets:
        return {}

    sites_file = packet / "sites.txt"
    sites_file.write_text("\n".join(sorted({u for _, u in targets})) + "\n")
    run_out = packet / "measure.json"
    rules_arg = ",".join(rule_paths)
    try:
        subprocess.run([str(binary), "run", "--config", "current", "--rules", rules_arg, "--sites", str(sites_file),
                        "--out", str(run_out), "--wait", "8", "--repeat", "1", "--concurrency", "2"],
                       env=_env(), capture_output=True, timeout=60 + 30 * len(targets))
    except subprocess.TimeoutExpired:
        pass
    by_site = {}
    if run_out.exists():
        for rec in json.loads(run_out.read_text()).get("results", []):
            by_site[rec.get("site")] = rec

    shots = packet / "shots"
    shots.mkdir(exist_ok=True)
    result = {}
    for i, (r, opened) in enumerate(targets, 1):
        rec = by_site.get(opened, {})
        hosts = third_party_hosts(rec.get("resources", []), r.get("domain") or "")
        shot_rel = f"shots/{i:02d}.png"
        try:
            subprocess.run([str(binary), "shoot", "--site", opened, "--rules", rules_arg,
                            "--out", str(packet / shot_rel), "--wait", "8"],
                           env=_env(), capture_output=True, timeout=90)
        except subprocess.TimeoutExpired:
            pass
        result[r["id"]] = {
            "opened_url": opened,
            "third_party": hosts,
            "ad_marked": ad_marked_hosts(hosts, ad_domains),
            "shot": shot_rel if (packet / shot_rel).exists() else "",
            "failed": bool(rec.get("failed", not rec)),
            "fail_reason": rec.get("failReason") or ("計測結果なし" if not rec else ""),
        }
    return result


def write_status(payload: dict) -> None:
    PACKETS_ROOT.mkdir(exist_ok=True)
    (PACKETS_ROOT / "status.json").write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")


def build(args) -> int:
    today = dt.datetime.now(JST).strftime("%Y-%m-%d")
    rows = d1_select(REPORT_QUERY)
    candidates = d1_select(CANDIDATE_QUERY)

    packet = PACKETS_ROOT / today
    packet.mkdir(parents=True, exist_ok=True)
    # 同じ日に作り直したとき、前回の画面が番号ずれで残らないようにする（束のフォルダの中だけ）
    shutil.rmtree(packet / "shots", ignore_errors=True)
    measurements = {}
    if not args.no_measure:
        rule_paths = fetch_cdn_rules(PACKETS_ROOT / ".rules")
        ad_domains = ad_domains_from(PACKETS_ROOT / ".rules")
        binary = measure_binary(PACKETS_ROOT / ".bin")
        measurements = measure_reports(rows, packet, rule_paths, ad_domains, binary, args.max_pages)

    (packet / "packet.md").write_text(render_packet(today, rows, measurements, candidates))
    (packet / "results-draft.json").write_text(
        json.dumps(results_draft(rows, today), ensure_ascii=False, indent=2) + "\n")

    for old in packets_to_prune(PACKETS_ROOT, keep=args.keep):
        shutil.rmtree(old)

    write_status({
        "built_at": dt.datetime.now(JST).isoformat(timespec="seconds"),
        "packet": str(packet / "packet.md"),
        "pending_reports": len(rows),
        "stalled_candidates": len(candidates),
        "measured_pages": len(measurements),
    })
    print(f"束を作成: {packet / 'packet.md'}（未判定 {len(rows)} 件・止まっている候補 {len(candidates)} 件・"
          f"計測 {len(measurements)} ページ）")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="A-88 週 1 回判定の束を作る（D1 は読み取りのみ）")
    ap.add_argument("--count-only", action="store_true", help="未判定の件数だけ表示する")
    ap.add_argument("--no-measure", action="store_true", help="報告ページの計測を省く")
    ap.add_argument("--max-pages", type=int, default=30, help="計測するページの上限")
    ap.add_argument("--keep", type=int, default=8, help="残す束の数（古いものから消す）")
    args = ap.parse_args()

    if args.count_only:
        print(d1_select(COUNT_QUERY)[0]["n"])
        return 0
    try:
        return build(args)
    except Exception as e:  # 失敗も status.json に残す（朝のレポート・起動時の案内が「作れなかった」と分かるように）
        write_status({"built_at": dt.datetime.now(JST).isoformat(timespec="seconds"), "error": str(e)[:500]})
        print(f"束の作成に失敗: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
