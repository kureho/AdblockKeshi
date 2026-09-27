#!/usr/bin/env python3
"""
scripts/measure/extract-block-domains.py

上限なし全量で変換した規則 JSON（例: combined_4_nolimit.json）から、
action.type == "block" かつ url-filter が「ドメイン固定形」
( ^[^:]+://+([^:/]+\\.)?example.com[/:] のような形。サブドメイン込みでそのドメイン
  全体を遮断するタイプの規則 ) のものだけを抜き出し、ホスト名の集合（広告・追跡ドメイン集合）
を作る。scripts/measure/measure.swift の「漏れ」判定（規則ありで開いたときに、この集合に
入っている通信が実際に読み込まれてしまっていないか）の基準に使う。

パス・クエリ限定の規則（&hitType=pageview& 等）はこの形にマッチしないため対象外
（＝この集合は「サイト全体を遮断する」規則だけの下限値）。

使い方:
  python3 scripts/measure/extract-block-domains.py <入力rules.json> <出力domains.txt>

2026-09-27 実測: combined_4_nolimit.json（226,877件・うち block 193,582件）に対して
171,628 件がこの形にマッチ・重複除去後 112,862 ドメイン（amoad.com・doubleclick.net 等を含む）。
"""
import json
import re
import sys

PREFIX = r'^[^:]+://+([^:/]+\.)?'
SUFFIXES = (r'[/:]\$', r'[/:]')
# ドメイン部分がさらに正規表現の特殊文字を含まない「素のドメイン」であることを確認する
DOMAIN_RE = re.compile(r'^[a-zA-Z0-9][a-zA-Z0-9\-]*(\\\.[a-zA-Z0-9][a-zA-Z0-9\-]*)*$')


def extract(rules):
    domains = set()
    block_count = 0
    for r in rules:
        if r.get('action', {}).get('type') != 'block':
            continue
        block_count += 1
        uf = r.get('trigger', {}).get('url-filter', '')
        if not uf.startswith(PREFIX):
            continue
        rest = uf[len(PREFIX):]
        for suf in SUFFIXES:
            if rest.endswith(suf):
                dom = rest[:len(rest) - len(suf)]
                if DOMAIN_RE.match(dom):
                    domains.add(dom.replace('\\.', '.'))
                break
    return domains, block_count


def main():
    if len(sys.argv) != 3:
        print('usage: extract-block-domains.py <in.json> <out.txt>', file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1], encoding='utf-8') as f:
        rules = json.load(f)
    domains, block_count = extract(rules)
    with open(sys.argv[2], 'w', encoding='utf-8') as f:
        for d in sorted(domains):
            f.write(d + '\n')
    print(f'rules={len(rules)} block={block_count} matched_domain_form={len(domains)} -> {sys.argv[2]}')


if __name__ == '__main__':
    main()
