#!/usr/bin/env python3
"""
scripts/review/fetch_page.py — 自動判定の Claude が報告ページの HTML を保存するための小さな道具（curl の代わり）

  python3 -I fetch_page.py <番号> <名前>

- 取れるのは束の sites.txt に載っている報告ページだけ（<番号> は 1 から）。URL は Claude に選ばせない
  ＝ほかの場所へ何かを送る道にしない
- 転送は http/https で、行き先が私的・ループバック・リンクローカルのアドレスでない時だけたどる（5 回まで）
- スマホの Safari の UA・最大 5MB・20 秒。保存先は作業場所の page-<名前>.html に固定（上書きはしない）
- 場所は auto_judge.py が環境変数で渡す: AUTO_JUDGE_SCRATCH・AUTO_JUDGE_SITES
"""
import ipaddress
import os
import re
import socket
import sys
import urllib.parse
import urllib.request
from pathlib import Path

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
MAX = 5 * 1024 * 1024


def check_target(url: str) -> None:
    u = urllib.parse.urlsplit(url)
    if u.scheme not in ("http", "https") or not u.hostname:
        raise ValueError("http/https だけ")
    for info in socket.getaddrinfo(u.hostname, u.port or (443 if u.scheme == "https" else 80)):
        ip = ipaddress.ip_address(info[4][0])
        if not ip.is_global:
            raise ValueError("行き先が外のアドレスでない")


def load_sites(path: Path) -> list[str]:
    """束の sites.txt を計測ツール（measure.swift の loadSites）と同じ規則で読む。スキームが無ければ https を付ける"""
    out = []
    for line in path.read_text().splitlines():
        t = line.strip()
        if not t or t.startswith("#") or t.startswith("SKIP"):
            continue
        out.append(t if t.startswith(("https://", "http://")) else "https://" + t)
    return out


def is_public(url: str) -> bool:
    try:
        check_target(url)
        return True
    except (ValueError, OSError):
        return False


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    max_redirections = 5

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        check_target(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def main() -> int:
    if len(sys.argv) != 3:
        print("使い方: fetch_page.py <番号> <名前>", file=sys.stderr)
        return 2
    num, name = sys.argv[1], sys.argv[2]
    try:
        scratch = Path(os.environ["AUTO_JUDGE_SCRATCH"])
        sites = load_sites(Path(os.environ["AUTO_JUDGE_SITES"]))
    except (KeyError, OSError) as e:
        print(f"場所が分からない: {e}", file=sys.stderr)
        return 2
    if not num.isdigit() or not 1 <= int(num) <= len(sites):
        print(f"番号は 1〜{len(sites)}", file=sys.stderr)
        return 2
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,60}", name):
        print("名前は英数字と _- だけ（60 文字まで）", file=sys.stderr)
        return 2
    out = scratch / f"page-{name}.html"
    if out.exists():
        print(f"もうある: {out}", file=sys.stderr)
        return 2
    url = sites[int(num) - 1]
    check_target(url)
    opener = urllib.request.build_opener(SafeRedirect)
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "ja-JP,ja;q=0.9"})
    with opener.open(req, timeout=20) as r:
        body = r.read(MAX + 1)
        final = r.geturl()
    out.write_bytes(body[:MAX])
    host = urllib.parse.urlsplit(final).hostname
    print(f"保存: {out}（{min(len(body), MAX)} バイト・最後の行き先のホスト {host}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
