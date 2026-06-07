<!-- [paid-approved-by-kureho] documentation only, no ASC API calls -->
# Plan D Task 1.4: v3.0 Privacy 文書 3 ソース整合性 audit

**目的**: v3.0 build を ASC 提出する前に、Privacy 関連の主張が 3 ソース間で一致していることを保証する。乖離があると Apple 5.1.1 (Privacy) reject リスクが高い。

**3 ソース**:
| ID | ソース | 場所 | 管理者 |
|---|---|---|---|
| **A** | Privacy Policy (Web) | `app-support/src/lib/products.ts` の `adblock-keshi.dataHandling.paragraphs` | Claude が PR で更新 |
| **B** | ASC App Privacy 入力 checklist | `AdblockKeshi/tasks/v3-asc-app-privacy-checklist.md` | Claude が更新 |
| **C** | ASC App Privacy (Nutrition Label) | App Store Connect Web UI | kureho が手動入力 |

**自動 verify**: `python3 tasks/scripts/audit_v3_privacy_consistency.py` で A ↔ B を照合（C は API 不可なので kureho 手動）。

---

## 必須主張 8 項目 (spec rev4 §6 rev3 出典)

| # | 主張 | A (privacy.tsx) | B (checklist md) | C (ASC UI) |
|---|---|---|---|---|
| 1 | 収集項目 = 報告 URL + メモ + UUID hash + IP hash の 4 つに限定 | dataHandling §2 で明示 | "Data Type 一覧" 3 項目を列挙 | "Data Linked to You" に User Content + Identifiers を宣言 |
| 2 | 保持期間 = 最大 14 日、集計後自動削除 | dataHandling §3 で明示 | (Web UI 側にフィールドなし、対応 N/A) | (該当フィールドなし) |
| 3 | 削除依頼 SLA = 24 時間以内自動処理 (実態 1 時間) | dataHandling §4 で明示 | "v2.x → v3.0 切り替え時の操作タイミング" 等で言及 | (該当フィールドなし) |
| 4 | 第三者提供なし / 広告ネットワーク・分析サービスへ送らない | dataHandling §3 末尾で明示 | "Used for Tracking?: No" | "Data Used to Track You: なし" |
| 5 | 保管インフラ = Cloudflare Workers/D1 APAC | dataHandling §3 で明示 | (Web UI 側にフィールドなし、N/A) | (該当フィールドなし) |
| 6 | abuse 4 段階 ban (24h / 7d / 30d / 永久) | dataHandling §5 で明示 | "Purposes: App Functionality (rate limit)" で間接的に表現 | "Purposes: App Functionality" |
| 7 | 緊急 kill switch あり (サーバー側) | dataHandling §6 で明示 | (Web UI 側にフィールドなし、N/A) | (該当フィールドなし) |
| 8 | Linked 判定 = rev3 安全側 (uuid_hash + ip_hash 複合キーで traceback 可能) | dataHandling §2 で「開発者だけが知るソルト」と表現 | "理由: 同一ハッシュ ID から複数報告を集計するため traceability あり" で明示 | "Linked to User: Yes" |

---

## 自動 audit script

```bash
python3 /Users/oharakureho/claude/AdblockKeshi/tasks/scripts/audit_v3_privacy_consistency.py
# verbose 出力
python3 /Users/oharakureho/claude/AdblockKeshi/tasks/scripts/audit_v3_privacy_consistency.py --verbose
```

期待出力 (3 ソース整合時):
```
✅ 収集項目 (URL/メモ/UUID hash/IP hash)
✅ 保持期間 14 日
✅ 削除依頼 24h SLA / 実態 1h
✅ 第三者提供なし / Tracking なし
✅ 保管インフラ Cloudflare Workers/D1 APAC
✅ abuse 4 段階 ban
✅ 緊急 kill switch
✅ Linked 判定 (rev3 安全側)
✅ A と B は整合。残るは C を kureho が目視確認するだけ。
```

exit code 0 = pass、1 = 乖離あり、2 = ファイル不在。

---

## C (ASC Web UI) 手動 verify 手順 (kureho)

1. App Store Connect → 広告消し (App ID 6774906945) → App Privacy
2. 以下の項目を目視確認:
   - **Data Linked to You** セクション
     - User Content > Other User Content: あり / Purposes に App Functionality
     - Identifiers > Device ID: あり / Purposes に App Functionality
   - **Data Used to Track You** セクション: 「None」(セクションごと表示されない)
   - 末尾の **Privacy Policy URL**: `https://kureho.app/privacy/adblock-keshi`
3. 同じ App Store Connect → App Information → **Subtitle / Privacy Policy URL** が App Privacy 側と一致するか
4. App Store の Product Page (シークレットウィンドウで一般ユーザー視点) で同じ情報が反映されているか (publish 直後は反映に 1〜2 時間)

---

## 整合性 verify のタイミング

| When | 何を |
|---|---|
| 本セッション末 | A と B の static audit (`audit_v3_privacy_consistency.py`) を pass 確認 |
| v3.0 build 提出直前 | kureho が ASC Web UI で C を本文書通りに入力 |
| v3.0 build 提出後 | ASC API で **Privacy Policy URL** が正しいか script で audit (今後追加予定) |
| v3.0 READY_FOR_SALE 化後 1〜2 時間 | App Store Product Page で C の反映を目視 |

---

## 関連

- spec: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §6
- AdblockKeshi PR #20 (ASC App Privacy checklist)
- app-support PR #6 (Privacy Policy `dataHandling`)
- script: `tasks/scripts/audit_v3_privacy_consistency.py`
- memory: [[feedback_apple_submission_state_audit]] (4 点監査) / [[feedback_asc_url_canonical_audit]] (URL 整合)
