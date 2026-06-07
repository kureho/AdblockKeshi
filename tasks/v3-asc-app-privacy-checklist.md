# v3.0 提出時 ASC App Privacy (Nutrition Label) チェックリスト

**前提**: ASC App Privacy (Nutrition Label) は **ASC Web UI 限定**で、公式 API は存在しない（Apple 公式 help でも UI workflow のみ記載、確認: 2026-06-07）。kureho が ASC Web UI で手動入力する際の指示書。

**Spec 出典**: `docs/superpowers/specs/2026-06-06-adblockkeshi-v3-learning-adblock-design.md` §6 Nutrition Label (rev3: 安全側で Linked 判定)

**Privacy Policy 整合先**: `app-support/src/lib/products.ts` の `adblock-keshi.dataHandling`（PR https://github.com/kureho/app-support/pull/6 ）

---

## v2.x → v3.0 切り替え時の操作タイミング

App Privacy section は **build と独立に変更可能**だが、配信中の build と整合しないと regulatory リスク。手順:

1. v3.0 build を ASC に upload + processing 完了 + AppStoreVersion 3.0.0 にアタッチ
2. **その AppStoreVersion を Apple Review に submit する直前** に App Privacy を本 checklist 通りに更新
3. App Privacy 更新は即座にライブ反映されるが、配信中の v2.x build に「Identifiers Linked」表示が出るのは 1〜2 時間（App Store サーバ反映待ち）
4. v3.0 build が READY_FOR_SALE 化したら整合完了

---

## ASC Web UI 操作手順

1. App Store Connect → 広告消し (App ID 6774906945) → **App Privacy** タブ
2. **Edit** ボタン → 「Yes, we collect data from this app」を選択
3. 以下の Data Type を順に追加し、各 Type で **Linked: Yes** / **Tracking: No** / **Purpose: App Functionality** を選ぶ

---

## 宣言すべき Data Type 一覧 (spec rev4 §6 rev3 安全側)

### 1. User Content > Other User Content

**対象**: 報告タブから送られた URL / 自由記述メモ

| 項目 | 値 |
|---|---|
| Data Collected? | ✅ Yes |
| Linked to User? | ✅ **Yes (rev3: 安全側)** |
| Used for Tracking? | ❌ No |
| Purposes | ✅ **App Functionality** のみ |

理由: `uuid_hash + ip_hash` 複合キーで同一ユーザー識別が可能なスキーマのため、Apple "Not Linked" の判定 (個別ユーザーへ traceback できない) を厳密に解釈すると **Linked** が安全。Tracking 用途は一切なし。

---

### 2. Identifiers > Device ID (UUID hash)

**対象**: 端末内で生成した UUID を SHA-256 ハッシュ化したもの (rate limit / abuse detection 用)

| 項目 | 値 |
|---|---|
| Data Collected? | ✅ Yes |
| Linked to User? | ✅ **Yes (rev3)** |
| Used for Tracking? | ❌ No |
| Purposes | ✅ **App Functionality** のみ |

理由: 同一ハッシュ ID から複数報告を集計するため traceability があり、Linked 扱いが正直。広告計測・第三者連携には使わないため Tracking は No。

---

### 3. Identifiers > Device ID (IP hash)

**対象**: クライアント IP を開発者だけが知るソルトで SHA-256 ハッシュ化したもの (多重投稿・abuse 検知用)

| 項目 | 値 |
|---|---|
| Data Collected? | ✅ Yes |
| Linked to User? | ✅ **Yes (rev3)** |
| Used for Tracking? | ❌ No |
| Purposes | ✅ **App Functionality** のみ |

理由: IP 自体は保持しないが、ハッシュ済みでも複数報告を関連付けられるため Linked 扱い。rate limit と abuse 検知のみに使用。

---

## 宣言してはいけない (Plan C で実装していないもの)

以下は **収集していない** ため declarations に追加しない（誤って追加すると規約違反扱い）:

- ❌ Contact Info (メール等) — 削除依頼用 `info@kureho.app` は ASC 側 Privacy Contact のみで、アプリ自体は収集しない
- ❌ Health & Fitness
- ❌ Financial Info
- ❌ Location (Precise / Coarse)
- ❌ Sensitive Info
- ❌ Contacts
- ❌ Browsing History — Safari 拡張は Content Blocker JSON を返すだけで閲覧履歴は通信しない (Apple SDK の制約)
- ❌ Search History
- ❌ Purchases
- ❌ Usage Data (Product Interaction, Advertising Data 等) — 解析 SDK なし
- ❌ Diagnostics (Crash Data, Performance Data 等) — Firebase / Sentry など導入なし
- ❌ Audio Data / Photos / Videos / Customer Support / Other Data Types — 該当なし

---

## 整合性 verify (kureho 操作)

1. ASC App Privacy で publish 完了後、App Store の Product Page をシークレットウィンドウで開き、**App Privacy セクション** が:
   - 「Data Linked to You」に「User Content」「Identifiers」が並ぶ
   - 「Data Used to Track You」セクションが **存在しない** (= None)
2. `https://kureho.app/privacy/adblock-keshi` の §2 (dataHandling 「報告データの取り扱い」) と Nutrition Label 表記が**完全に一致**
3. ASC App Privacy 末尾の **Privacy Policy URL** が `https://kureho.app/privacy/adblock-keshi` を指す

---

## 関連メモリ

- [[feedback_corp_review_info_only]] — App Review Information は法人情報のみ
- [[feedback_apple_submission_state_audit]] — 提出後 4 点監査必須

## 関連 PR / spec

- AdblockKeshi spec rev4 §6
- AdblockKeshi PR #18 (RemoteConfig + ban-engine 基盤)
- AdblockKeshi PR #19 (moat 可視化)
- app-support PR #6 (Privacy Policy `dataHandling`)
