#!/usr/bin/env python3
"""
scripts/review/build_review_packet.py — A-88 §2「報告の週 1 回判定」の下ごしらえ

Claude なしで毎週自動で走り（launchd・Mac 上）、判定用の束を手元に作る:
  1. 本番 D1 から未判定の報告（reports.review_outcome IS NULL）と、止まっているルール候補
     （rule_candidates.status = 'kureho_queue'）を**読み取りのみ**で取る
  2. Safari で見た報告は、報告されたページを計測ツール（scripts/measure/measure.swift＝iOS Safari と
     同じ規則エンジン）で「今配信中の規則」のまま開き、残っている通信先と画面を集める
     ★詐欺サイトの種類（ad_type = phishing）の報告はページを開かない（A-218 設計 §3-2）。代わりに
     配信中の 3 万件にあるか・HaGeZi の全部にあるか・ブランドの語・共有ホストの下か・登録日（RDAP）を並べる
  3. .review-packets/YYYY-MM-DD/ に packet.md（判定用）・results-draft.json（結果の下書き）・
     shots/（画面）を書き、.review-packets/status.json に件数を残す

判定そのものは次に開いたセッションで Claude が行い、結果を review/results/ に書く
（書き方は review/results/README.md）。D1 への書き込みはこのスクリプトでは一切しない。

★このリポジトリは公開。報告の URL・メモ・画面は .review-packets/（.gitignore 済み）にだけ置く。

使い方:
  python3 scripts/review/build_review_packet.py              # 束を作る（週 1 回の本番）
  python3 scripts/review/build_review_packet.py --count-only # 未判定の件数だけ表示（朝のレポート用）
  python3 scripts/review/build_review_packet.py --no-measure # D1 だけ読んで束を作る（計測を省く）
  python3 scripts/review/build_review_packet.py --scam-source <HaGeZi の一覧>  # 詐欺サイトの報告の照合に手元の一覧を使う
                                                                                 #（省略時は配信元から取る）
"""
from __future__ import annotations

import argparse
import datetime as dt
import functools
import http.client
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable
from urllib.parse import urlsplit, urlunsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "measure"))
from build_security_rules import (  # noqa: E402
    _HOST_RE,
    DEFAULT_JP_TOKENS,
    DEFAULT_SHARED_PARENTS,
    JPTokens,
    SourceTooSmall,
    _ancestors,
    _is_shared,
    check_declared_entries,
    load_jp_tokens,
    load_shared_parents,
    parse_phishing_db_hosts,
)
from security_list_report import hosts_from_rules  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
WORKERS = REPO / "workers"
PACKETS_ROOT = REPO / ".review-packets"
D1_DATABASE = "adblockkeshi-reports"
# wrangler が 1 時間ごとのログイン更新をした回の問い合わせは、約半分が 7403（このアカウントには権限が無い）で
# 断られる（2026-10-12 に wrangler の実行ログ 79 回で実測: 更新した 23 回のうち 12 回が 7403・更新しなかった回の
# 7403 はゼロ）。断られる内部の理由は未確認（実際に送ったトークンはログに残らない）。失敗の次の呼び出しが更新なしなら
# 4 組とも通ったので、7403 のときだけ待って 1 回取り直す。10 秒は暫定値（秒単位で取り直した実例は約 5 秒の 1 組だけ）。
D1_RETRY_WAIT_SEC = 10
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

# A-218 詐欺サイトの報告の事実。HaGeZi の取得先は .github/workflows/build-security-rules.yml と同じ物
SCAM_AD_TYPE = "phishing"
HAGEZI_TIF_URL = "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/wildcard/tif-onlydomains.txt"
RDAP_URL = "https://rdap.org/domain/"
RDAP_MAX_TRIES = 3                  # 2 ラベルから上へ、最大 3 回まで引く
SCAM_RECENT_DAYS = 90               # 基準 B-2「登録から 90 日以内」
HTTP_USER_AGENT = "AdblockKeshi-review/1.0"
_IPV4_RE = re.compile(r"^\d{1,3}(\.\d{1,3}){3}$")


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
        port = parts.port
    except ValueError:
        return None
    if parts.scheme != "https" or not host or "." not in host:
        return None
    # 利用者名・パスワード（user:pass@）は利用者の物になり得る＝開く時に送らない
    netloc = f"{host}:{port}" if port else host
    return urlunsplit((parts.scheme, netloc, parts.path or "/", "", ""))


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


def is_scam_report(row: dict) -> bool:
    """詐欺サイトの種類の報告か（アプリの表示「詐欺サイト」＝ad_type phishing）。"""
    return row.get("ad_type") == SCAM_AD_TYPE


def _url_host(url: str | None) -> str | None:
    opened = page_url_for_measure(url)
    return normalize_report_host(urlsplit(opened).hostname) if opened else None


def scam_reported_hosts(rows: list[dict]) -> set[str]:
    """詐欺サイトとして報告されたホスト（報告のドメインと、報告の URL のホスト）。"""
    hosts = set()
    for r in rows:
        if is_scam_report(r):
            hosts.update(h for h in (normalize_report_host(r.get("domain")), _url_host(r.get("url"))) if h)
    return hosts


def _opens_scam_host(row: dict, scam_hosts: set[str]) -> bool:
    host = _url_host(row.get("url"))
    return bool(host and scam_hosts and _covering(host, scam_hosts))


def measure_targets(rows: list[dict], max_pages: int) -> list[tuple[dict, str]]:
    """計測ツールで開く報告と、開く URL。ほかのアプリの報告と、詐欺サイトの種類の報告は開かない。
    詐欺サイトとして報告されたホスト（とその下）は、別の種類の報告からも開かない。"""
    scam_hosts = scam_reported_hosts(rows)
    targets = []
    for r in rows:
        if r.get("seen_in") == "other_app" or is_scam_report(r) or _opens_scam_host(r, scam_hosts):
            continue
        opened = page_url_for_measure(r.get("url"))
        # 照合できない形のホスト（%で書いた点など）は、開くと別の名前として扱われ得る＝開かない
        if opened and _url_host(opened):
            targets.append((r, opened))
    return targets[:max_pages]


def normalize_report_host(domain: str | None) -> str | None:
    """報告のドメイン（受付で URL の host を保存＝ポートが付き得る）を小文字のホストにする。形が違えば None。"""
    if not domain:
        return None
    host = domain.strip().lower()
    if ":" in host:
        host, _, port = host.rpartition(":")
        if not port.isdigit():
            return None
    host = host.rstrip(".")
    if (len(host) > 253 or not _HOST_RE.fullmatch(host)
            or any(len(label) > 63 for label in host.split("."))):
        return None
    return host


def rdap_candidates(host: str) -> list[str]:
    """登録日を引く名前の候補。末尾 2 ラベルから 1 つずつ上へ（example.co.uk のような形のため）。"""
    labels = host.split(".")
    return [".".join(labels[-n:]) for n in range(2, len(labels) + 1)][:RDAP_MAX_TRIES]


def rdap_registration_date(payload: dict) -> str | None:
    """RDAP の答えから登録日（YYYY-MM-DD）を取る。無い・形が違えば None。"""
    events = payload.get("events") if isinstance(payload, dict) else None
    if not isinstance(events, list):
        return None
    for ev in events:
        if isinstance(ev, dict) and ev.get("eventAction") == "registration":
            date = str(ev.get("eventDate") or "")[:10]
            try:
                dt.date.fromisoformat(date)
            except ValueError:
                return None
            return date
    return None


def _covering(host: str, hosts: set[str]) -> str | None:
    """規則と同じ意味で host を覆う物（host 自身か、その上）。無ければ None。"""
    for h in [host] + _ancestors(host):
        if h in hosts:
            return h
    return None


def _brand_words(host: str, tokens: JPTokens, shared_parent: str | None) -> list[str]:
    """ドメインに入っているブランドの語（jp-priority-tokens の jp・brand は含む物、jp-token は語として一致）。
    見るのは持ち主が決めた部分だけ: 共有ホストの下なら共有ホストより左、ほかは最後のラベルを除いた部分。"""
    if _IPV4_RE.match(host):
        return []
    body = host[: -(len(shared_parent) + 1)] if shared_parent else host.rsplit(".", 1)[0]
    words = set(re.split(r"[.-]", body))
    found = [t for t in tokens.jp + tokens.brand if t in body]
    found += [t for t in tokens.jp_token if t in words]
    return sorted(set(found))


def scam_facts(domain: str | None, *, served: set[str] | None, source: set[str] | None, tokens: JPTokens,
               shared_parents: set[str], lookup: Callable[[str], str | None], today: dt.date,
               source_note: str = "") -> dict:
    """詐欺サイトの報告 1 件の、見直しで使う事実（設計 §3-2 の「配信中にあるか」と B の 1・2）。

    served / source が None なら、その一覧は取れなかった（＝未確認）。lookup は登録日を引く関数
    （本番は rdap_lookup。試験では差し替える）。報告のページは開かない。"""
    host = normalize_report_host(domain)
    facts = {
        "host": host, "invalid": host is None,
        "served": None, "served_known": served is not None,
        "source": None, "source_known": source is not None, "source_note": source_note,
        "brand_words": [], "shared_parent": None,
        "registered": None, "registered_domain": None, "age_days": None, "rdap_note": "",
    }
    if host is None:
        return facts
    if served is not None:
        facts["served"] = _covering(host, served)
    if source is not None:
        facts["source"] = _covering(host, source)
    if _is_shared(host, shared_parents):
        facts["shared_parent"] = host
        facts["rdap_note"] = "共有ホストそのもの（一覧の除外で外れる＝載らない）。登録日は引いていない"
        return facts
    shared = next((a for a in _ancestors(host) if _is_shared(a, shared_parents)), None)
    facts["shared_parent"] = shared
    facts["brand_words"] = _brand_words(host, tokens, shared)

    if _IPV4_RE.match(host):
        facts["rdap_note"] = "IP アドレス（ドメインの登録日は無い）"
        return facts
    if shared:
        facts["rdap_note"] = f"共有ホスト（{shared}）の下＝登録日は場所の持ち主の物で根拠にならない（引いていない）"
        return facts
    for cand in rdap_candidates(host):
        date = lookup(cand)
        if date:
            age = (today - dt.date.fromisoformat(date)).days
            if age < 0:
                facts["rdap_note"] = f"RDAP の登録日が未来（{date}・{cand}）＝信用しない"
                return facts
            facts["registered"] = date
            facts["registered_domain"] = cand
            facts["age_days"] = age
            return facts
    facts["rdap_note"] = "RDAP で登録日が取れなかった（RDAP の無い TLD〔.jp など〕・時間切れ・回数の制限のどれか）"
    return facts


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


def _scam_lines(f: dict | None) -> list[str]:
    lines = ["- 詐欺サイトの報告: **ページは開いていない**（開くと相手に見に来た事が伝わる・悪い仕掛けに触れ得る）。"
             "載せる基準は review/scam-domains/README.md"]
    if not f:
        return lines + ["- ドメインの事実: 取れなかった"]
    if f.get("invalid"):
        return lines + ["- ドメインの事実: 報告のドメインの形が不正で調べていない"]
    lines.append(f"- 調べたドメイン: {f['host']}")
    if not f["served_known"]:
        lines.append("- 配信中の 3 万件: 未確認（配信中の一覧を読めなかった）")
    elif f["served"]:
        lines.append(f"- 配信中の 3 万件: **あり**（{f['served']}）＝一覧に足す話ではない"
                     "（保護を切っている・「このサイトで一時オフ」・アプリの不具合のどれか）")
    else:
        lines.append("- 配信中の 3 万件: なし")
    if not f["source_known"]:
        lines.append(f"- 基準 B-1 HaGeZi の全部: 未確認（{f.get('source_note') or '一覧を読めなかった'}）")
    elif f["source"]:
        lines.append(f"- 基準 B-1 HaGeZi の全部: **あり**（{f['source']}）")
    else:
        lines.append("- 基準 B-1 HaGeZi の全部: なし")
    words = f.get("brand_words") or []
    lines.append("- 基準 B-2 ブランドの語: " + (", ".join(words) + "（公式のドメインでないかは見直しで確かめる）"
                                              if words else "なし"))
    if f["shared_parent"] and f["shared_parent"] == f["host"]:
        lines.append("- 共有ホスト: 報告のドメインが共有ホストそのもの（一覧の除外で外れる＝載らない）")
    else:
        lines.append(f"- 共有ホストの下: {f['shared_parent'] or 'いいえ'}")
    if f.get("registered"):
        age = f["age_days"]
        within = f"{SCAM_RECENT_DAYS} 日以内" if age <= SCAM_RECENT_DAYS else f"{SCAM_RECENT_DAYS} 日より前"
        lines.append(f"- 登録日（RDAP）: {f['registered']}（{f['registered_domain']}・{age} 日前＝{within}）")
    else:
        lines.append(f"- 登録日（RDAP）: 未確認（{f.get('rdap_note') or '取れなかった'}）")
    return lines


def render_packet(date: str, rows: list[dict], measurements: dict, candidates: list[dict],
                  scam: dict | None = None) -> str:
    scam = scam or {}
    scam_hosts = scam_reported_hosts(rows)
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
        "- 詐欺サイトの種類の報告はページを開かず、ドメインの事実だけを並べる（A-218）",
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
        if is_scam_report(r):
            lines += _scam_lines(scam.get(r["id"]))
            lines.append("")
            continue
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
        elif not suggestion and _opens_scam_host(r, scam_hosts):
            lines.append("- 計測: 詐欺サイトとして報告されたホストなので開いていない（同じ束の詐欺サイトの報告を見る）")
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


def _wrangler_error(proc) -> str:
    """失敗した wrangler の理由を短く取り出す（stdout の JSON → stderr → stdout の末尾の順）。"""
    try:
        err = json.loads(proc.stdout).get("error") or {}
        parts = [err.get("text", "")] + [n.get("text", "") for n in err.get("notes", [])]
        text = " / ".join(p for p in parts if p)
        if text:
            return text[-300:]
    except (ValueError, AttributeError):
        pass
    return (proc.stderr.strip() or proc.stdout.strip())[-300:]


def _refused_7403(proc) -> bool:
    """ログイン更新の直後に断られた失敗か（stdout の JSON の error.code、または理由の文の [code: 7403]）。"""
    try:
        if (json.loads(proc.stdout).get("error") or {}).get("code") == 7403:
            return True
    except (ValueError, AttributeError):
        pass
    return "[code: 7403]" in _wrangler_error(proc)


def d1_select(sql: str) -> list[dict]:
    """wrangler（この Mac のログイン）で本番 D1 に SELECT を 1 本流す。書き込みはしない。

    取り直すのは 7403 で断られた 1 回だけ（D1_RETRY_WAIT_SEC の注）。表が無い・SQL の誤りのような
    直らない失敗はすぐ止める（朝のレポートを待たせない）。120 秒のタイムアウトも取り直さずそのまま上げる。
    """
    if not sql.lstrip().upper().startswith("SELECT"):
        raise ValueError("読み取り（SELECT）以外は流さない")
    for attempt in (1, 2):
        proc = subprocess.run(
            ["npx", "wrangler", "d1", "execute", D1_DATABASE, "--remote", "--json", "--command", sql],
            cwd=WORKERS, env=_env(), capture_output=True, text=True, timeout=120,
        )
        if proc.returncode == 0 or attempt == 2 or not _refused_7403(proc):
            break
        time.sleep(D1_RETRY_WAIT_SEC)
    if proc.returncode != 0:
        # wrangler は --json のとき失敗の理由を stdout の JSON（error.text と error.notes）に出し、
        # stderr は空になる（2026-10-12 実測）。stderr だけ見ていたので理由が毎回空だった。
        raise RuntimeError(f"wrangler d1 execute が失敗（exit {proc.returncode}）: {_wrangler_error(proc)}")
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
    targets = measure_targets(rows, max_pages)
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


def rdap_lookup(domain: str) -> str | None:
    """rdap.org（各登録所の RDAP へ転送する無料の入口）で登録日を引く。取れなければ None（＝未確認）。
    domain は normalize_report_host を通した名前だけを渡す（URL にそのまま入る）。"""
    time.sleep(1.0)  # rdap.org の回数の制限に当たらないように
    req = urllib.request.Request(RDAP_URL + domain,
                                 headers={"Accept": "application/rdap+json", "User-Agent": HTTP_USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            payload = json.loads(resp.read(2_000_000))
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError):
        return None
    return rdap_registration_date(payload)


def served_scam_hosts() -> set[str] | None:
    """公開中（origin/main）の詐欺サイトの一覧（docs/cdn/security-rules.json・3 万件）のホスト。読めなければ None。
    取り直し（git fetch）に失敗した時も None: 手元の古い origin/main を「配信中」と言うと、既に外れた
    ドメインを「配信中にあり＝足す話ではない」と見せてしまう。"""
    try:
        fetched = subprocess.run(["git", "fetch", "--quiet", "origin", "main"], cwd=REPO, env=_env(),
                                 capture_output=True, timeout=120)
        if fetched.returncode != 0:
            return None
        proc = subprocess.run(["git", "show", "origin/main:docs/cdn/security-rules.json"], cwd=REPO, env=_env(),
                              capture_output=True, timeout=120)
    except (subprocess.TimeoutExpired, OSError):
        return None
    if proc.returncode != 0:
        return None
    try:
        hosts = set(hosts_from_rules(json.loads(proc.stdout)))
    except (ValueError, AttributeError):
        return None
    return hosts or None


def scam_source_hosts(path: str | None) -> tuple[set[str] | None, str]:
    """HaGeZi の全部の一覧のホスト。path が無ければ配信元から取る。取れない・途中で切れた時は (None, 理由)。"""
    try:
        if path:
            text = Path(path).read_text(encoding="utf-8", errors="replace")
        else:
            req = urllib.request.Request(HAGEZI_TIF_URL, headers={"User-Agent": HTTP_USER_AGENT})
            with urllib.request.urlopen(req, timeout=300) as resp:
                text = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, http.client.HTTPException, OSError, ValueError) as e:
        return None, f"一覧を取れなかった（{type(e).__name__}）"
    hosts = parse_phishing_db_hosts(text)
    if not hosts:
        return None, "一覧が空だった"
    try:
        check_declared_entries(text, len(hosts))
    except SourceTooSmall as e:
        return None, f"一覧が途中で切れている（{e}）"
    return {h.lower() for h in hosts}, ""


def collect_scam_facts(rows: list[dict], source_path: str | None, today: dt.date) -> dict:
    """詐欺サイトの報告ごとの事実（report_id → scam_facts）。同じドメインの登録日は 1 回だけ引く。"""
    served = served_scam_hosts()
    source, note = scam_source_hosts(source_path)
    tokens = load_jp_tokens(DEFAULT_JP_TOKENS)
    shared: set[str] = set()
    for path in DEFAULT_SHARED_PARENTS:
        shared |= load_shared_parents(path)
    lookup = functools.lru_cache(maxsize=None)(rdap_lookup)
    return {r["id"]: scam_facts(r.get("domain"), served=served, source=source, tokens=tokens,
                                shared_parents=shared, lookup=lookup, today=today, source_note=note)
            for r in rows}


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

    # 詐欺サイトの報告はページを開かず、ドメインの事実だけを集める（A-218）。
    # 取れなくても束は作る（束には「取れなかった」と出る）
    scam_rows = [r for r in rows if is_scam_report(r)]
    scam = {}
    if scam_rows:
        try:
            scam = collect_scam_facts(scam_rows, args.scam_source, dt.datetime.now(JST).date())
        except Exception as e:  # noqa: BLE001
            print(f"詐欺サイトの報告の事実を取れなかった: {e}", file=sys.stderr)

    (packet / "packet.md").write_text(render_packet(today, rows, measurements, candidates, scam))
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
          f"計測 {len(measurements)} ページ・詐欺サイトの報告 {len(scam_rows)} 件）")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="A-88 週 1 回判定の束を作る（D1 は読み取りのみ）")
    ap.add_argument("--count-only", action="store_true", help="未判定の件数だけ表示する")
    ap.add_argument("--no-measure", action="store_true", help="報告ページの計測を省く")
    ap.add_argument("--max-pages", type=int, default=30, help="計測するページの上限")
    ap.add_argument("--keep", type=int, default=8, help="残す束の数（古いものから消す）")
    ap.add_argument("--scam-source", help="詐欺サイトの報告の照合に使う HaGeZi の一覧（省略時は配信元から取る）")
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
