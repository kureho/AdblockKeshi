#!/usr/bin/env python3
"""
scripts/review/fetch_page.py — 自動判定の Claude が報告ページの HTML を保存するための小さな道具（curl の代わり）

  python3 -I fetch_page.py <URL> <名前>

- http/https だけ・スマホの Safari の UA・最大 5MB・20 秒
- 保存先は環境変数 AUTO_JUDGE_SCRATCH のフォルダの中だけ（名前に / や .. は使えない）。上書きはしない
- Claude にファイルの送り出しや任意の場所への書き込みをさせないため、curl は渡していない（auto_judge.py）
"""
import os
import re
import sys
import urllib.request
from pathlib import Path

UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1")
MAX = 5 * 1024 * 1024


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: fetch_page.py <URL> <名前>", file=sys.stderr)
        return 2
    url, name = sys.argv[1], sys.argv[2]
    scratch = os.environ.get("AUTO_JUDGE_SCRATCH")
    if not scratch:
        print("AUTO_JUDGE_SCRATCH が無い", file=sys.stderr)
        return 2
    if not re.fullmatch(r"https?://[^\s]+", url):
        print("http/https の URL だけ", file=sys.stderr)
        return 2
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,60}", name):
        print("名前は英数字と _- だけ（60 文字まで）", file=sys.stderr)
        return 2
    out = Path(scratch) / f"page-{name}.html"
    if out.exists():
        print(f"もうある: {out}", file=sys.stderr)
        return 2
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Language": "ja-JP,ja;q=0.9"})
    with urllib.request.urlopen(req, timeout=20) as r:
        body = r.read(MAX + 1)
        final = r.geturl()
    out.write_bytes(body[:MAX])
    print(f"保存: {out}（{min(len(body), MAX)} バイト・最後の URL の場所 {final.split('?')[0][:120]}）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
