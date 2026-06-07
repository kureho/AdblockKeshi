#!/usr/bin/env python3
"""Plan D Task 1.4: v3.0 Privacy 文書 3 ソース整合性 audit.

Sources:
  A. app-support/src/lib/products.ts の adblock-keshi.dataHandling.paragraphs
  B. AdblockKeshi/tasks/v3-asc-app-privacy-checklist.md
  C. ASC App Privacy Web UI (kureho manual, ASC public API では編集不可)

Static check (this script): A と B 両方に必須主張 8 項目が含まれるか正規表現で照合。
Manual check (kureho): C と上記項目の整合 (詳細は tasks/v3-privacy-consistency-audit.md)。

Usage:
  python3 tasks/scripts/audit_v3_privacy_consistency.py
  python3 tasks/scripts/audit_v3_privacy_consistency.py --verbose

Exit codes:
  0 = A と B 整合
  1 = 乖離あり (どの項目が欠けたか stderr に詳細)
  2 = ファイル不在 / 構造異常
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]  # /Users/oharakureho/claude
A_PATH = REPO_ROOT / "app-support" / "src" / "lib" / "products.ts"
B_PATH = REPO_ROOT / "AdblockKeshi" / "tasks" / "v3-asc-app-privacy-checklist.md"


# 各 claim について A と B に求める正規表現 (リストの全要素が一致すれば pass)。
# B が "N/A" (= []) のときは A だけ check。
REQUIRED_CLAIMS = [
    {
        "key": "collection_items",
        "label": "収集項目 (URL/メモ/UUID hash/IP hash)",
        "patterns_a": [r"報告対象 URL", r"メモ", r"UUID", r"IP"],
        # B (checklist md) では「報告タブから送られた URL / 自由記述メモ」
        # と書かれているので「URL」「メモ」を個別に。
        "patterns_b": [r"URL", r"メモ", r"UUID hash", r"IP hash"],
    },
    {
        "key": "retention_14d",
        "label": "保持期間 14 日",
        "patterns_a": [r"14\s*日"],
        # B (Nutrition Label checklist) には保持期間フィールドが無いため
        # 必須 pattern なし (audit doc Matrix で N/A と明記済)。
        "patterns_b": [],
    },
    {
        "key": "deletion_sla",
        "label": "削除依頼 24h SLA / 実態 1h",
        "patterns_a": [r"24\s*時間", r"1\s*時間"],
        # B には削除依頼の数値フィールドが無いため、「v2.x → v3.0 切り替え
        # 時の操作タイミング」等での言及 (タイミング or 24 時間 キーワード)
        # があれば十分。
        "patterns_b": [r"タイミング|24\s*時間"],
    },
    {
        "key": "no_third_party",
        "label": "第三者提供なし / Tracking なし",
        "patterns_a": [r"第三者", r"広告配信ネットワーク"],
        "patterns_b": [r"Tracking", r"Tracking 用途は一切なし"],
    },
    {
        "key": "infra_cloudflare_apac",
        "label": "保管インフラ Cloudflare Workers/D1 APAC",
        "patterns_a": [r"Cloudflare", r"Asia-Pacific"],
        "patterns_b": [r"App Functionality"],  # B は purpose 表現で十分
    },
    {
        "key": "abuse_ban_4_levels",
        "label": "abuse 4 段階 ban",
        "patterns_a": [r"4\s*段階", r"ban"],
        "patterns_b": [r"rate limit"],
    },
    {
        "key": "kill_switch",
        "label": "緊急 kill switch (サーバー側)",
        "patterns_a": [r"サーバー側|機能停止"],
        "patterns_b": [],  # B (Nutrition Label) は kill switch 言及対象外
    },
    {
        "key": "linked_safe_side",
        "label": "Linked 判定 (rev3 安全側)",
        "patterns_a": [r"ソルト"],
        "patterns_b": [r"Linked", r"rev3"],
    },
]


def load_text(path: Path) -> str:
    if not path.exists():
        print(f"❌ NOT FOUND: {path}", file=sys.stderr)
        return ""
    return path.read_text(encoding="utf-8")


def extract_adblock_keshi_data_handling(products_ts: str) -> str:
    """Extract the adblock-keshi.dataHandling block from products.ts.

    The file is large (~3000 lines). We grep from `slug: "adblock-keshi"` to
    the next product slug entry.
    """
    m = re.search(r'slug:\s*"adblock-keshi"', products_ts)
    if not m:
        return ""
    start = m.start()
    # 次の product entry (e.g. personalizedalarm: {) または末尾まで
    tail = products_ts[start:]
    e = re.search(r"\n  \w+:\s*\{\s*\n\s*key:\s*\"", tail[1000:])  # 少なくとも 1000 文字後ろ
    end = start + 1000 + e.start() if e else len(products_ts)
    return products_ts[start:end]


def main(verbose: bool = False) -> int:
    a_full = load_text(A_PATH)
    b_full = load_text(B_PATH)

    if not a_full or not b_full:
        return 2

    a_section = extract_adblock_keshi_data_handling(a_full)
    if not a_section:
        print(
            f"❌ A から adblock-keshi.dataHandling ブロックを抽出できませんでした: {A_PATH}",
            file=sys.stderr,
        )
        return 2

    print("=== Privacy 文書 3 ソース整合性 audit (Plan D Task 1.4) ===\n")
    print(f"A. app-support products.ts (adblock-keshi block) — {len(a_section)} chars")
    print(f"B. AdblockKeshi/tasks/v3-asc-app-privacy-checklist.md — {len(b_full)} chars\n")

    rc = 0
    for claim in REQUIRED_CLAIMS:
        a_misses = [p for p in claim["patterns_a"] if not re.search(p, a_section)]
        b_misses = [p for p in claim["patterns_b"] if not re.search(p, b_full)]
        a_ok = not a_misses
        b_ok = not b_misses
        ok = a_ok and b_ok
        status = "✅" if ok else "⚠️"
        print(f"{status} {claim['label']}")
        if verbose or not ok:
            print(f"     A patterns ok: {a_ok} (miss: {a_misses})")
            print(f"     B patterns ok: {b_ok} (miss: {b_misses})")
        if not ok:
            rc = 1

    print()
    print("=== C. ASC App Privacy Web UI (kureho 手動 verify) ===")
    print("以下を ASC Web UI で目視確認してください (詳細: tasks/v3-privacy-consistency-audit.md):")
    print("  1. Data Linked to You: User Content > Other User Content がある")
    print("  2. Data Linked to You: Identifiers > Device ID がある")
    print("  3. Data Used to Track You: なし (= None)")
    print("  4. Privacy Policy URL: https://kureho.app/privacy/adblock-keshi")
    print()

    if rc == 0:
        print("✅ A と B は整合。残るは C を kureho が ASC Web UI で目視確認するだけ。")
    else:
        print("⚠️ A と B に乖離あり。各文書を spec rev4 §6 通りに揃えてください。")

    return rc


if __name__ == "__main__":
    verbose = "--verbose" in sys.argv or "-v" in sys.argv
    sys.exit(main(verbose=verbose))
