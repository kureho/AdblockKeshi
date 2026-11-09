# 広告消し: 詐欺サイト対策を看板にし、アプリ内のリンクも止める 実装計画（A-218）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 詐欺サイトの一覧を「元の並び順で打ち切り」から「日本向け優先＋偏らない選び方」に直し（G0）、その一覧を看板の第 1 弾で前に出し（G1）、買い切りの DNS（アプリ内広告ブロック）でも詐欺ドメインを止め（G2）、それを看板の第 2 弾で言う（G3）。

**Architecture:** 選び方は `scripts/build_security_rules.py` の 1 つの関数 `select_hosts(..., profile="safari"|"dns")` に集め、Safari 用（3 万件・今の形式のまま）と DNS 用（別ファイル `dns-security.txt`・優先順の 1 行 1 ドメイン）を同じ元データから別々に作る。DNS 側は旧版に届かないよう**別の配信ファイル**にし、端末では 1 件 8 バイトのハッシュの並び（`DNSHashedDomainSet`）で持ってメモリを抑え、「詐欺サイトブロック」のスイッチ（`state.json` の `securityEnabled`）に従う。G1・G3 は掲載情報と画像で、kureho のレビューと提出の承認を関門にする。

**Tech Stack:** Python 3.12 + pytest（`scripts/`）／Swift 5.10・XCTest・NetworkExtension（`Shared/DNS`・`PacketTunnelExtension`）／XcodeGen／GitHub Actions + GitHub Pages（`docs/cdn`）／macOS の WebKit（規則のコンパイル確認）

**Spec:** `docs/superpowers/specs/2026-11-09-scam-link-protection-design.md`（kureho 承認 2026-11-09）
**調査:** `tasks/security-positioning-research-2026-11-09.md`（数字・出典はこちらが正）

## 実装進捗（durable マーカー・終えたら ✅ と日付・証拠の場所を書く）

- [x] G0: Task A1〜A5（一覧の直し・計測）→ 🙋 kureho の承認 → Task A6（配信）— ✅ 2026-11-09 配信（kureho 承認「URLhaus を外して配る」・merge b099578・週次の手動実行 42575996084 → 7c13674・CDN から取り直して計測と同じ物を確認）。証拠 `tasks/a218-g0-measurement-2026-11-09.md`
- [ ] G1: Task B1〜B6（G0 の配信後の次の版）
- [ ] G2: Task C1〜C7
- [ ] G3: Task D1（G2 の版と同時か直後）

## Global Constraints

- **main に入れた時点で配信される**: `.github/workflows/build-security-rules.yml` は毎週日曜 0:13 UTC に main の `scripts/build_security_rules.py` を動かし `docs/cdn/` へ push する（旧版の利用者にもアプリの更新なしで届く）。G0・G2 のスクリプトの変更は**ブランチで作って計測し、kureho の承認の後に main へ入れる**（spec §5「配信物を変える前に計測し、kureho の承認を取る」）
- Safari の規則は 1 本 15 万件まで。詐欺の枠は 2 本目（報告反映）の末尾 **30,000 件固定**（A-88）・大きさは `SECURITY_MAX_BYTES` = 4,000,000 まで。規則の書き方（`^[^:]+://+([^:/]+\.)?<host>[/:]`・`|` を使わない）は変えない（旧版がそのまま読む）
- 元の一覧: Phishing.Database ACTIVE（MIT）＋ URLhaus（CC0）。**Tranco 上位は誤ブロック避けで除外**。重要ドメインは止めない（`CriticalDomainGuard`・`DNSCriticalGuard`）
- 共有ホスティングの**親ドメインそのもの**（`github.io`・`blogspot.com`・`weebly.com`・`000webhostapp.com` など）は入れない（その下の個別のサブドメインは入れてよい）。Safari 用と DNS 用は同じ元データから別々に選び、計測も別々に出す
- DNS（アプリ内広告ブロック）の詐欺ブロックは**買い切りの人だけ**・「詐欺サイトブロック」のスイッチに従う・一時停止（15 分・1 時間）が効く・**止めた時は何も出さない**・判定は端末内（新しく外へ送るデータは無い）。DNS 用は Safari 用より厳しく選ぶ
- GitHub Actions のワークフローを変える時は kureho の明示承認と `timeout-minutes`
- 掲載情報（名前・副題・キーワード・宣伝文・説明文）に **Safari・iPhone・Apple・価格を書かない**（5.2.5・2.3.7）。LINE などの他社名も名前・副題・キーワードには入れない
- 文言 §7: 言ってよい「既知の詐欺サイト・フィッシングサイトの一覧と照らして止める」「詐欺サイトをブロック」「判定は端末内」「サブスクなし（説明文で）」／言わない「ウイルス対策・ウイルススキャン・検知・AI で判定・すべて防ぐ・100%・安全を保証・情報漏えいを防ぐ」／必ず添える「新しい詐欺サイトは、一覧に載るまで止められないことがある」／無料と買い切りの境界を説明文で明記
- 新しい有料サービスは使わない（Web Risk 不使用）
- **G0 の配信が済むまで G1 を出さない**。審査提出・本番の配信は kureho の承認（同じ時に出る物は 1 回にまとめて見せてよい）
- 実装はこのアプリ単体を開いたタブで行う。app-support（サポートサイト）は別の案件なのでそのタブで行う
- Swift のファイルを足したら `xcodegen generate` の後に試験する。NetworkExtension の実行時の確認は**実機だけ**（シミュレータはビルドと純関数の試験まで）

## Review Focus

試験が直接は通らないが、使う人に一番効きそうな 5 つ。各行の試験は持ち主のタスクに入れてある。

1. **取得の失敗で守りが外れる**: Tranco が途中で切れて数件しか無いと「除外」が効かず人気サイトを止める。Phishing.Database が切れると一覧が痩せる → 下限を割ったら止める（Task A2 `test_check_sources_*`）
2. **皆が使う共有のホストが一覧に入る**: `storage.googleapis.com`・`lin.ee`・`bit.ly` のようにパスで多数の利用者が同居するホストを止めると、普通のリンクまで開かなくなる → 共有ホストの一覧で除く（Task A2 `test_select_drops_shared_hosts_*`）
3. **スイッチを切っても DNS が止め続ける／一覧が無いと読み込みが回り続ける**: アプリからの通知は落ちることがある。また「一覧が見つからない」を「オフ」と取り違えると 5 秒ごとに作り直す → 要求した値で比べる（Task C5 `DNSSecurityToggleSyncTests`）
4. **一覧が育って拡張がメモリで落ちる**: 落ちるとトンネルが切れる → 端末でも上限で切り、件数は実測で決める（Task C2 `test_maxCount_*`・Task C6）
5. **配信ファイルの行の揺れで取りこぼす**: 大文字・末尾のドット・CRLF・コメント行で読み込みと照会の正規化がずれる（Task C2 `test_normalizes_*`）

---

## ファイル構造

**G0（Python・計測）**
- Modify: `scripts/build_security_rules.py` — 選び方（`select_hosts`）・除外・下限の確かめ・DNS 用の書き出し（G2）
- Create: `scripts/data/jp-priority-tokens.txt` — 日本向けの見分けに使う語（kureho が読める形）
- Create: `scripts/data/shared-hosting-parents.txt` — 親そのものは入れない共有ホスト
- Modify: `scripts/tests/test_build_security_rules.py`
- Create: `scripts/measure/security_list_report.py` + `scripts/tests/test_security_list_report.py` — 直す前後の計測の表
- Create: `scripts/measure/compile_rules_webkit.swift` — macOS の WebKit で規則をコンパイルできるか
- Create: `scripts/measure/data/jp-phish-sample-<YYYY-MM>.txt` — 日本向けの詐欺ドメインの見本（出典つき・ライセンスが許す時だけコミット）
- Create: `tasks/a218-g0-measurement-<YYYY-MM-DD>.md` — 計測の結果（kureho に見せる物）

**G2（Swift）**
- Create: `Shared/DNS/DNSHashedDomainSet.swift` — 1 行 1 ドメインのデータから作る省メモリの集合
- Create: `Shared/DNS/DNSSecurityListStore.swift` — App Group → 同梱 → 無し の順に読む
- Create: `Shared/DNS/DNSSecurityToggleSync.swift` — スイッチの状態の取りこぼし回収の判定
- Create: `Shared/DNS/MemoryFootprint.swift` — 実測用（`phys_footprint` と最大値）
- Modify: `Shared/DNS/DNSEngine.swift`・`Shared/DNS/DNSCriticalGuard.swift`・`Shared/DNS/DNSUpdatePlanner.swift`・`Shared/DNS/DNSListUpdater.swift`
- Modify: `PacketTunnelExtension/PacketTunnelProvider.swift`・`App/BlockerControlView.swift`・`App/AdblockKeshiApp.swift`・`project.yml`
- Create: `PacketTunnelExtension/Resources/dns-security.txt`・`docs/cdn/dns-security.txt`・`docs/cdn/version-dns-security.json`
- Modify: `.github/workflows/build-security-rules.yml`（🙋 承認）
- Test: `Tests/DNSHashedDomainSetTests.swift`・`Tests/DNSSecurityListStoreTests.swift`・`Tests/DNSSecurityToggleSyncTests.swift`・`Tests/MemoryFootprintTests.swift`、既存 `Tests/DNSEngineTests.swift`・`Tests/DNSCriticalGuardTests.swift`・`Tests/DNSUpdatePlannerTests.swift`・`Tests/DNSListUpdaterTests.swift`・`Tests/BlockerControlViewModelTests.swift` に追記

**G1・G3（掲載・同梱）**
- Modify: `fastlane/metadata/ja/{name,subtitle,keywords,promotional_text,description,release_notes}.txt`
- Create: `scripts/tests/test_store_metadata_wording.py` — §7 と 5.2.5・2.3.7 の機械的な確かめ
- Modify: `Extension/Resources/security-rules.json`・`App/Resources/second-ads-sec.json`・`App/Resources/bundled-rules-info.json`
- Create: `tasks/release-<版>-consistency.md`（今までの照合表の形）

---

## G0 一覧の選び方を直す

### Task A1: 計測の材料と、選び方に使う語・共有ホストの一覧を作る

**Files:**
- Create: `scripts/data/jp-priority-tokens.txt`・`scripts/data/shared-hosting-parents.txt`・`scripts/measure/data/jp-phish-sample-<YYYY-MM>.txt`
- 元データの取得先: `$SCRATCH/a218-g0/src/`（`$SCRATCH` はそのセッションの scratchpad の絶対パス。以下のタスクも同じ。コミットしない）

**Interfaces:**
- Produces: 2 つのデータファイル（下の形）。Task A2・A3 の `load_shared_parents(path) -> set[str]`・`load_jp_tokens(path) -> JPTokens` が読む

- [ ] **Step 1: 元データを取る**（ワークフローと同じ URL・無料・認証なし。取ったファイルは空の新しいディレクトリに置き、Python は `-I` で動かす）
  - URLhaus `https://urlhaus.abuse.ch/downloads/hostfile/`
  - Phishing.Database `https://raw.githubusercontent.com/mitchellkrogza/Phishing.Database/master/phishing-domains-ACTIVE.txt`
  - Tranco 最新の上位 100 万（`build-security-rules.yml` の取り方と同じ）
  - Public Suffix List `https://publicsuffix.org/list/public_suffix_list.dat`（共有ホストの確かめだけに使う）
  - 期待: 行数を記録（Phishing.Database は 2026-11-09 に 392,178 件）

- [ ] **Step 2: 日本向けの見本を作る**
  - 第 1 候補: JPCERT/CC の `phishurl-list`（GitHub）の直近 2 か月分から URL のホスト名を取る。第 2 候補（取れない・止まっている時）: フィッシング対策協議会の緊急情報の直近 3 か月分
  - ファイルの頭に `# 出典 URL / 期間 / 取得日 / 件数` を書く。50 件以上を目安。重複は除く
  - 出典のライセンスを読み、再配布が許されない時はコミットせず `tasks/` には出典と取り方だけ書く

- [ ] **Step 3: 共有ホストの一覧を決める**
  - 下の初期値の各行が PSL の private 節にあるかを確かめて、ファイルのコメントに残す
  - 元の一覧の中で「直下のサブドメインが 20 件以上ある親」を多い順に 50 件出し、サービスの公式サイトで「利用者にサブドメインやパスを貸すサービス」と確かめられた物を足す
  - 初期値（1 行 1 ホスト・`#` はコメント）:
    - サブドメインを貸す: `github.io gitlab.io blogspot.com weebly.com weeblysite.com wixsite.com 000webhostapp.com firebaseapp.com web.app pages.dev workers.dev netlify.app vercel.app herokuapp.com glitch.me onrender.com azurewebsites.net square.site godaddysites.com webflow.io r2.dev ngrok-free.app myshopify.com wordpress.com duckdns.org`
    - パスで同居する・短縮 URL: `storage.googleapis.com firebasestorage.googleapis.com ipfs.io dweb.link cloudflare-ipfs.com forms.gle goo.gl bit.ly tinyurl.com is.gd cutt.ly rebrand.ly lin.ee`

- [ ] **Step 4: 日本向けの語のファイルを作る**（行頭の印で 3 種。照合は Task A3）
  ```
  # 日本向け（ホスト名から最後のラベルを除いた部分に含まれれば当たり）
  jp: rakuten aeon saison paypay mercari docomo softbank ymobile kddi smbc vpass mufg mizuho resona yucho jpbank jp-bank japanpost jppost sagawa kuroneko yamato ekinet eki-net etax e-tax mynumber myna jcb orico eposcard jaccs japan nihon nippon
  # 日本向け（「.」「-」で区切った語と完全一致・最後のラベルは見ない）
  jp-token: jp nta au
  # 日本でもよく偽装される海外ブランド（含まれれば当たり）
  brand: amazon apple microsoft netflix paypal visa mastercard amex
  ```
  - 元の一覧で各語の件数を数え、調査 §4-4 の数（`amazon` 3,694・`rakuten` 482・`aeon` 151・`nta-` 90・`paypay` 79・`saison` 56）と桁が合うことを確かめる

- [ ] **Step 5: 新しさの扱いを確かめて記録する**
  - Phishing.Database に新着だけのファイル（NEW-today 等）があるかをリポジトリで確かめ、`tasks/a218-g0-measurement-*.md` の「決めたこと」に書く。**G0 では新しさは使わない**（ACTIVE は「今も生きている」で既に絞られている。新着の履歴を持つには配信側に状態が要る）

- [ ] **Step 6: Commit**（ブランチ `feat/a218-g0-list-selection` を main から切ってから）
  ```bash
  git switch -c feat/a218-g0-list-selection
  git add scripts/data/ scripts/measure/data/ docs/superpowers/specs/2026-11-09-scam-link-protection-design.md tasks/security-positioning-research-2026-11-09.md docs/superpowers/plans/2026-11-09-scam-link-protection.md
  git commit -m "A-218 G0: 選び方に使う語・共有ホスト・日本向けの見本を足す"
  ```

### Task A2: 除外と下限の守り（安全側）

**Files:**
- Modify: `scripts/build_security_rules.py`
- Test: `scripts/tests/test_build_security_rules.py`

**Interfaces:**
- Consumes: Task A1 のデータファイル
- Produces:
  - `@dataclass(frozen=True) class JPTokens: jp: tuple[str, ...]; jp_token: tuple[str, ...]; brand: tuple[str, ...]`（中身の使い方は Task A3。A2 の試験は空の `NO_TOKENS = JPTokens((), (), ())` を使う）
  - `class SourceTooSmall(Exception)`
  - `TRANCO_MIN = 900_000`・`PHISHING_MIN = 100_000`・`DNS_POPULAR_TOP = 100_000`
  - `check_sources(tranco_count: int, phishing_count: int) -> None`（下限未満で `SourceTooSmall`）
  - `load_protected_domains(swift_paths: list[Path]) -> set[str]`（Swift の `Set<String> = [ ... ]` の中の文字列だけを読む）
  - `PROTECTED_SWIFT = {"safari": [Shared/CriticalDomainGuard.swift], "dns": [Shared/CriticalDomainGuard.swift, Shared/DNS/DNSCriticalGuard.swift]}`（リポジトリ根からのパス）
  - `load_shared_parents(path: Path) -> set[str]`
  - `load_tranco_ranked(text: str) -> list[str]`（順位の順）
  - `exclusion_reason(host: str, *, profile: str, tranco_closure: set[str], popular: set[str], protected: set[str], shared_parents: set[str]) -> str | None`（除く理由の短い名前か None。計測の表がそのまま使う）

除く条件（両方の profile）:
- `invalid`: 今の `_HOST_RE` に合わない
- `shared-parent`: 共有ホストそのもの
- `protected`: 重要ドメインそのもの・その下・その上（その上を止めると重要ドメインごと止まる）
- `tranco`: Tranco 100 万のどれかと同じか、その上（`tranco_closure` = 全ドメインとその上の全て）

DNS だけ:
- `ip`: IPv4 の数字だけのホスト（DNS の問い合わせ名にならない）
- `popular-parent`: 上のどれかが Tranco 上位 10 万（`popular`）にあり、それが共有ホストでない（人気サイトの乗っ取られたサブドメインは、DNS では端末全体のアプリに効くので入れない）

Safari では `github.io` の下は入れてよい（`github.io` は `DNSCriticalGuard` にだけある）。

- [ ] **Step 1: 失敗する試験を書く**

```python
def test_check_sources_rejects_truncated_tranco():
    with pytest.raises(SourceTooSmall):
        check_sources(tranco_count=1_000, phishing_count=392_178)

def test_check_sources_rejects_truncated_phishing_db():
    with pytest.raises(SourceTooSmall):
        check_sources(tranco_count=1_000_000, phishing_count=50_000)
    check_sources(tranco_count=1_000_000, phishing_count=392_178)  # 例外なし

def test_load_protected_domains_reads_set_literals_only():
    safari = load_protected_domains([ROOT / "Shared/CriticalDomainGuard.swift"])
    assert {"apple.com", "smbc.co.jp", "kureho.app"} <= safari
    assert "github.io" not in safari
    dns = load_protected_domains([ROOT / "Shared/CriticalDomainGuard.swift", ROOT / "Shared/DNS/DNSCriticalGuard.swift"])
    assert "github.io" in dns and len(safari) >= 50

def test_select_drops_shared_hosts_and_keeps_their_subdomains_on_safari():
    out = select_hosts([], ["github.io", "evil-login.github.io", "storage.googleapis.com", "lin.ee", "bit.ly", "x.weebly.com"],
                       [], protected=set(), shared_parents={"github.io", "storage.googleapis.com", "lin.ee", "bit.ly", "weebly.com"},
                       jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert sorted(out) == ["evil-login.github.io", "x.weebly.com"]

def test_select_never_blocks_a_tranco_domain_or_protected_domain():
    out = select_hosts([], ["example.com", "smbc.co.jp", "login.smbc.co.jp", "co.jp", "smbc-co-jp.evil.test"],
                       ["shop.example.com"], protected={"smbc.co.jp"}, shared_parents=set(),
                       jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert out == ["smbc-co-jp.evil.test"]

def test_dns_profile_is_stricter_than_safari():
    src = ["1.2.3.4", "hacked.popular.test", "evil.weebly.com", "evil-login.github.io"]
    kw = dict(protected={"github.io"}, shared_parents={"weebly.com", "github.io"}, jp_tokens=NO_TOKENS, limit=100)
    tranco = ["popular.test", "weebly.com"]
    assert sorted(select_hosts([], src, tranco, profile="dns", **kw)) == ["evil.weebly.com"]
    assert "hacked.popular.test" in select_hosts([], src, tranco, profile="safari", **kw)
```
（`NO_TOKENS` は空の `JPTokens`。`select_hosts` の形は Task A3 の Interfaces。A2 では順番を問わない試験だけ書く）

- [ ] **Step 2: 失敗を確かめる**
  Run: `python3 -m pytest scripts/tests/test_build_security_rules.py -q`
  Expected: 新しい試験が ImportError / NameError で FAIL

- [ ] **Step 3: 実装する**（上の Interfaces どおり。`select_hosts` は A2 の時点では元の並び順のまま除外だけ行ってよい。`main()` は読み込んだ直後に `check_sources(len(tranco_ranked), len(phishing_hosts))` を呼ぶ。CLI の引数は変えない＝今のワークフローのまま動く）

- [ ] **Step 4: 通ることを確かめる**
  Run: `python3 -m pytest scripts/tests/ -q`
  Expected: 全て PASS（既存の 14 本を含む）

- [ ] **Step 5: Commit** `git commit -m "A-218 G0: 共有ホスト・重要ドメイン・Tranco の除外と、元データの下限の確かめ"`

### Task A3: 並べ方（日本向けを優先・残りは偏らない順）

**Files:**
- Modify: `scripts/build_security_rules.py`
- Test: `scripts/tests/test_build_security_rules.py`

**Interfaces:**
- Consumes: Task A2 の除外関数・データの読み込み
- Produces:
  - `load_jp_tokens(path: Path) -> JPTokens`（`JPTokens` は Task A2）
  - `jp_priority(host: str, tokens: JPTokens) -> int`（0 = 日本向け〈`.jp` で終わる・`jp` の語・`jp-token` の語〉／1 = 海外ブランド／2 = その他）
  - `stable_key(host: str) -> str`（`hashlib.sha256(host.encode()).hexdigest()`）
  - `URLHAUS_CAP = 10_000`
  - `select_hosts(urlhaus_hosts: list[str], phishing_hosts: list[str], tranco_ranked: list[str], *, protected: set[str], shared_parents: set[str], jp_tokens: JPTokens, profile: str, limit: int, urlhaus_cap: int = URLHAUS_CAP) -> list[str]` — 返す順＝優先順
  - `build_security_rules(urlhaus_text, phishing_db_text, tranco_text, limit=30000, max_bytes=build_split_rules.SECURITY_MAX_BYTES)` は今の引数のまま、中で `select_hosts(profile="safari")` → `convert_to_content_blocker_rules` を呼ぶ（データファイルと重要ドメインは既定の場所から読む）。**優先順に足していき、`build_split_rules.list_bytes` で測った大きさが `max_bytes` を超える 1 本手前で止める**（2 本目の末尾は件数だけでなくバイトにも上限 4,000,000 がある。今は 30,000 件で 3,332,598・平均のホスト名 24.6 文字で、日本向けの長いホスト名が増えると超えうる）。`main()` は結果が 15,000 件未満なら止める（`replace_security_tail` の「前回の半分未満」と同じ線）

並べ方（並べ替えるだけで、元の一覧に無いホストは 1 件も足さない＝誤ブロックの危険は元データと同じ）:
1. 段 0: 日本向け（両方の元データから）
2. 段 1: URLhaus の残り（`stable_key` の順で `urlhaus_cap` まで）
3. 段 2: 海外ブランド
4. 段 3: その他
各段の中は `stable_key` の順。上から `limit` 件。元の並び順・入力の順には左右されない。

- [ ] **Step 1: 失敗する試験を書く**

```python
TOKENS = JPTokens(jp=("smbc", "rakuten"), jp_token=("nta", "au", "jp"), brand=("amazon",))

def test_jp_priority():
    assert jp_priority("smbc-card-login.test", TOKENS) == 0
    assert jp_priority("foo.co.jp", TOKENS) == 0
    assert jp_priority("au-pay-check.test", TOKENS) == 0
    assert jp_priority("amazon-verify.test", TOKENS) == 1
    assert jp_priority("santa-claus.test", TOKENS) == 2   # nta は語の完全一致だけ
    assert jp_priority("shop.com.au", TOKENS) == 2       # 最後のラベルは見ない
    assert jp_priority("random-site.test", TOKENS) == 2

def test_select_orders_jp_then_urlhaus_then_brand_then_rest():
    out = select_hosts(["mal.test"], ["zz.test", "amazon-x.test", "rakuten-x.test"], [],
                       protected=set(), shared_parents=set(), jp_tokens=TOKENS, profile="safari", limit=10)
    assert out == ["rakuten-x.test", "mal.test", "amazon-x.test", "zz.test"]

def test_select_remainder_follows_stable_hash_not_alphabet():
    src = [f"{c}{i}.test" for c in "0123456789abcdefghij" for i in range(50)]  # 名前順の 1,000 件
    out = select_hosts([], src, [], protected=set(), shared_parents=set(), jp_tokens=NO_TOKENS, profile="safari", limit=100)
    assert out == sorted(src, key=stable_key)[:100]

def test_select_is_independent_of_input_order():
    src = [f"h{i}.test" for i in range(300)]
    kw = dict(protected=set(), shared_parents=set(), jp_tokens=TOKENS, profile="safari", limit=50)
    assert select_hosts([], src, [], **kw) == select_hosts([], list(reversed(src)), [], **kw)

def test_urlhaus_tier_is_capped():
    out = select_hosts([f"m{i}.test" for i in range(30)], [f"p{i}.test" for i in range(30)], [],
                       protected=set(), shared_parents=set(), jp_tokens=NO_TOKENS, profile="safari", limit=40, urlhaus_cap=10)
    assert sum(h.startswith("m") for h in out) == 10

def test_build_security_rules_output_format_unchanged_for_old_clients():
    rules = build_security_rules("", "\n".join(f"phish-{i}.example" for i in range(50)), "", limit=30)
    assert len(rules) == 30
    assert all(re.fullmatch(r"\^\[\^:\]\+://\+\(\[\^:/\]\+\\\.\)\?[a-z0-9_\\.-]+\[/:\]", r["trigger"]["url-filter"]) for r in rules)
    assert all(r["action"] == {"type": "block"} for r in rules)

def test_build_security_rules_stops_before_byte_cap_in_priority_order():
    src = "\n".join(f"phish-{i}.example" for i in range(10))
    full = build_security_rules("", src, "", limit=10)
    cap = list_bytes(full[:5])
    capped = build_security_rules("", src, "", limit=10, max_bytes=cap)
    assert capped == full[:5]
```

既存の `test_build_security_rules_fills_limit_even_with_malformed_hosts` の `rules[0]` の行（元の並び順を前提にしている）は次に置き換える:
```python
    hosts = {r["trigger"]["url-filter"] for r in rules}
    assert len(rules) == 5
    assert hosts <= {f"^[^:]+://+([^:/]+\\.)?phish-{i}\\.example[/:]" for i in range(10)}
```

- [ ] **Step 2: 失敗を確かめる** Run: `python3 -m pytest scripts/tests/test_build_security_rules.py -q` → 新しい試験が FAIL
- [ ] **Step 3: 実装する**（上の Interfaces どおり）
- [ ] **Step 4: 通ることを確かめる** Run: `python3 -m pytest scripts/tests/ -q` → 全て PASS
- [ ] **Step 5: Commit** `git commit -m "A-218 G0: 詐欺サイトの一覧を日本向け優先・偏らない順で選ぶ"`

### Task A4: 計測の表と、WebKit でのコンパイル確認

**Files:**
- Create: `scripts/measure/security_list_report.py`・`scripts/tests/test_security_list_report.py`・`scripts/measure/compile_rules_webkit.swift`

**Interfaces:**
- Consumes: `select_hosts`・`exclusion_reason`・`jp_priority`・`load_*`（Task A2・A3）、`build_split_rules.replace_security_tail`・`list_bytes`・`SECURITY_MAX_BYTES`・`LIST_MAX_BYTES`
- Produces:
  - `hosts_from_rules(rules: list[dict]) -> list[str]`（`url-filter` からホストを戻す）
  - `load_hosts(path: Path) -> list[str]`（`.json` は Safari の規則、`.txt` は 1 行 1 ドメイン＝G2 の DNS 用）
  - `matches(host: str, selected: set[str]) -> bool`（規則と同じ意味: 同じか、その下。見本が「元の一覧にあるか」もこれで見る）
  - `report(old_rules, new_rules, *, urlhaus_hosts, phishing_hosts, tranco_ranked, protected, jp_sample, second_ads_sec: list[dict] | None) -> dict`（`second_ads_sec` が None なら 2 本目の確かめは飛ばす＝DNS 用）
  - CLI: `python3 scripts/measure/security_list_report.py --old <json|txt|none> --new <json|txt> --urlhaus <txt> --phishing-db <txt> --tranco <csv> --jp-sample <txt> [--second-ads-sec docs/cdn/second-ads-sec.json] --profile safari|dns --out <md>`（`--profile` は重要ドメインの読み先〈Task A2 の `PROTECTED_SWIFT`〉を選ぶ。dns では IPv4 が 0 件であることも表に出す）

表に出す物（直す前と後を並べる）:
- 件数・IPv4・数字始まり・英字始まり
- 段ごとの件数（新しい一覧）
- 日本向けの見本: ①見本のうち**元の一覧にあるか**（元データの拾う力）②その中で**選ばれたか**（選び方の質）を分けて、件数と割合
- 調査 §4-4 の語（`amazon`・`rakuten`・`aeon`・`nta-`・`paypay`・`saison`・`smbc`）の件数: 元の一覧／前／後
- 誤ブロック: Tranco 上位 1 万と重要ドメインのうち、規則に当たる数（後は 0 でなければならない）
- 前の一覧のうち新しい除外で外れる数と、理由ごとの見本 20 件
- 大きさ: `list_bytes(new) <= SECURITY_MAX_BYTES`、`replace_security_tail` を今の `second-ads-sec.json` に当てた結果（成功／失敗・件数 ≤ 150,000・バイト ≤ `LIST_MAX_BYTES`）

- [ ] **Step 1: 失敗する試験を書く**（小さい手作りの入力で）
```python
def test_report_separates_source_coverage_from_selection():
    r = report(old_rules=to_rules(["a.test"]), new_rules=to_rules(["a.test", "b.test"]),
               urlhaus_hosts=[], phishing_hosts=["a.test", "b.test"], tranco_ranked=["ok.test"],
               protected={"bank.test"}, jp_sample=["x.b.test", "b.test", "gone.test"], second_ads_sec=None)
    assert r["jp_sample"] == {"n": 3, "in_source": 2, "selected_old": 0, "selected_new": 2}

def test_report_counts_false_blocks():
    r = report(old_rules=[], new_rules=to_rules(["ok.test", "bank.test"]), urlhaus_hosts=[], phishing_hosts=[],
               tranco_ranked=["www.ok.test"], protected={"bank.test"}, jp_sample=[], second_ads_sec=None)
    assert r["false_blocks_new"] == {"tranco_top10k": 1, "protected": 1}

def test_hosts_from_rules_round_trips():
    assert hosts_from_rules(convert_to_content_blocker_rules(["a-b.example.co.jp", "1.2.3.4"])) == ["a-b.example.co.jp", "1.2.3.4"]
```
（`to_rules` は `convert_to_content_blocker_rules` の別名でよい）

- [ ] **Step 2: 失敗を確かめる** Run: `python3 -m pytest scripts/tests/test_security_list_report.py -q` → FAIL
- [ ] **Step 3: 実装する**（`report()` は dict を返し、`--out` で Markdown の表にする）
- [ ] **Step 4: 通ることを確かめる** Run: `python3 -m pytest scripts/tests/ -q` → 全て PASS
- [ ] **Step 5: WebKit のコンパイル確認を作る**: `compile_rules_webkit.swift` は引数の JSON を `WKContentRuleListStore(url: 一時ディレクトリ).compileContentRuleList(forIdentifier:encodedContentRuleList:)` でコンパイルし、成功なら `OK <件数> rules <秒>s` を出して終了コード 0、失敗ならエラーを出して 1（`scripts/check-popunder-rules-webkit.swift` と同じく macOS の WebKit を使う）
  Run: `swiftc -O scripts/measure/compile_rules_webkit.swift -o "$SCRATCH/compile" -framework WebKit -framework AppKit && "$SCRATCH/compile" docs/cdn/security-rules.json`
  Expected: `OK 30000 rules …`。`|` を含む規則 1 本の手作りファイルでは終了コード 1
- [ ] **Step 6: Commit** `git commit -m "A-218 G0: 一覧の直す前後の計測の表と WebKit のコンパイル確認"`

### Task A5: 実データで計測し、kureho に数字を見せる（🙋 関門）

**Files:**
- Create: `tasks/a218-g0-measurement-<YYYY-MM-DD>.md`

- [ ] **Step 1: 新しい一覧を作る**（Task A1 の元データで。ワークフローと同じ引数）
  Run: `python3 -I scripts/build_security_rules.py --urlhaus … --phishing-db … --tranco … --output "$SCRATCH/a218-g0/new/security-rules.json" --limit 30000`
  Expected: `Wrote 30000 rules`。バイトの上限で 30,000 未満になったら件数とバイトを表に書き、Step 5 の問いにも件数を書く（15,000 以上なら旧版も受け取る）
- [ ] **Step 2: 計測の表を出す**: `security_list_report.py` を `--old docs/cdn/security-rules.json --new <Step 1>` で
  合格の線: 後の誤ブロック 0（Tranco 上位 1 万・重要ドメイン）／`SECURITY_MAX_BYTES` 以下／`replace_security_tail` 成功・2 本目が 150,000 件以下かつ `LIST_MAX_BYTES` 以下／数字始まりの偏りが消えている／日本向けの見本の「選ばれた」が前より上
- [ ] **Step 3: 2 本目を組んで WebKit でコンパイルする**: `python3 scripts/build_split_rules.py swap-security --second docs/cdn/second-ads-sec.json --old-security docs/cdn/security-rules.json --new-security <Step 1> --output "$SCRATCH/a218-g0/new/second-ads-sec.json"` → `compile_rules_webkit` を新しい `security-rules.json` と `second-ads-sec.json` の両方に
  Expected: 両方 `OK`
- [ ] **Step 4: 結果を `tasks/a218-g0-measurement-*.md` に書く**: 表・合格の線との照合・決めたこと（語・共有ホスト・新しさを使わない理由・段の順）・言えないこと（見本は 1 か月分で、詐欺サイトは寿命が短い等）・配信の手順（Task A6）
- [ ] **Step 5: 🙋 kureho に聞く**（選ぶ窓。問いは「この選び方の一覧を、今の利用者（旧版を含む）へ配ってよいか」。選択肢: 配る（推奨・Task A6 へ）／直してから見せる）。数字の要点（数字始まりの偏り・日本向けの見本で止められる割合・誤ブロック 0）を問いの中に書く
- [ ] **Step 6: Commit** `git add tasks/a218-g0-measurement-*.md && git commit -m "A-218 G0: 計測の結果"`

### Task A6: 配信して、届いた物を確かめる（承認の後だけ）

- [ ] **Step 1**: `git switch main && git merge --no-ff feat/a218-g0-list-selection && git push origin main`
- [ ] **Step 2**: `gh workflow run build-security-rules.yml` → `gh run watch <id>`。Expected: 成功・`chore(security): weekly auto-update` のコミット
- [ ] **Step 3**: `git pull`。配信中の物を取り直し（`https://kureho.github.io/AdblockKeshi/cdn/security-rules.json`・`second-ads-sec.json`・`version-security.json`）、`security_list_report.py` を配信中の物で回し、Task A5 と同じ合格の線を満たすこと（誤ブロック 0・数字始まりの偏りなし・件数が同じ桁。ワークフローは元データを取り直すので数字そのものは一致しない）。`version-security.json` の sha が配信物と一致すること
- [ ] **Step 4**: 失敗した時: ワークフローは止まれば CDN を前の版のまま残す（`swap-security` の守り）。壊れた物が出た時は `git revert` のコミットを push して `workflow_dispatch` で戻す（kureho に報告）
- [ ] **Step 5**: 台帳 A-218 の「今どこ」と、この計画の「実装進捗」を更新

---

## G1 看板の第 1 弾（G0 の配信後の次の版）

各タスクの終わりは「出せる状態になった物」。提出・配信は Task B6 でまとめて kureho の承認。

### Task B1: 指標の起点を記録する

- [ ] App Store の表示回数・新規 DL・購入（apps-metrics-dashboard）と「広告ブロック」の順位（`tasks/aso-snapshot-2026-06-17.md` と同じ取り方）を、G1 の配信日の前 4 週について `tasks/a218-metrics.md` に記録する。配信後 4 週の見直しの日を台帳 B に足す（名前を戻す基準 spec §8: 表示回数が前の 4 週を下回り、かつ「広告ブロック」が 20 位以上落ちたら、次の版で名前を戻す）

### Task B2: 無料の人の動きを実機で確かめる（🙋 kureho の手が要る）

- [ ] **Step 1**: 配信中の `security-rules.json` から、Mac で `dig +short` が空（名前が引けない）のホストを 3 件選ぶ（止まらなかった時に本物の詐欺ページが開かないように）
- [ ] **Step 2**: kureho の実機で、アプリ内広告ブロック（DNS）を切った状態（＝無料の人と同じく Safari の拡張だけが効く）で: 報告反映オン・「詐欺サイトブロック」オンで本体ブラウザから 3 件を開く → 「コンテンツブロッカーによってブロックされました」の表示。報告反映オフ → 「サーバが見つからない」の表示（＝止めていたのは報告反映）
- [ ] **Step 3**: アプリの案内（`App/OnboardingView.swift` の「3 つすべてを ON」）が報告反映をオンにするところまで導くかを、初回起動からたどって確かめる。導いていなければ、この版で案内を直す（画面の変更なので作った物を kureho のレビューに出す）
- [ ] **Step 4**: 結果を `tasks/release-<版>-consistency.md` の「実機」節に書く

### Task B3: 掲載の文言（叩き台 → kureho のレビュー）

**Files:**
- Create: `scripts/tests/test_store_metadata_wording.py`
- Modify: `fastlane/metadata/ja/{name,subtitle,keywords,promotional_text,description,release_notes}.txt`

- [ ] **Step 1: 失敗する試験を書く**
```python
FILES = ["name", "subtitle", "keywords", "promotional_text", "description", "release_notes"]
BANNED = ["safari", "iphone", "apple", "ウイルス", "検知", "すべて防", "100%", "保証", "情報漏", "円", "¥"]

@pytest.mark.parametrize("name", FILES)
def test_no_banned_words(name):
    text = (META / f"{name}.txt").read_text()
    assert [w for w in BANNED if w in text.lower()] == []
    assert re.search(r"(?<![A-Za-z])AI(?![A-Za-z])", text) is None   # 「AI」は大文字の単語だけ（mail・domain に当てない）

@pytest.mark.parametrize("name", ["name", "subtitle", "keywords"])
def test_no_other_company_names_in_name_subtitle_keywords(name):
    assert "LINE" not in (META / f"{name}.txt").read_text().upper()

def test_lengths():
    assert len((META / "name.txt").read_text().strip()) <= 30
    assert len((META / "subtitle.txt").read_text().strip()) <= 30
    assert len((META / "keywords.txt").read_text().strip()) <= 100

def test_description_states_limits_and_tiers():
    d = (META / "description.txt").read_text()
    assert "一覧に載るまで" in d
    assert "無料" in d and "買い切り" in d
```
- [ ] **Step 2: 失敗を確かめる** Run: `python3 -m pytest scripts/tests/test_store_metadata_wording.py -q` → FAIL（★今の `description.txt` に「Safari」4 か所と「Apple」1 か所、`promotional_text.txt` に「Safari」1 か所がある。spec §6-2 は「今の説明文と同じく本体ブラウザと書く」としているが手元のファイルとは違う。ASC の今の文も取り寄せて照合し、違いを照合表に書く）
- [ ] **Step 3: 叩き台を書く**（spec §6-2 の叩き台から: 名前「広告消し - 詐欺サイト・広告ブロック」・副題「詐欺サイトも広告も、開く前に止める」。説明文の冒頭を詐欺サイト対策に。「無料でできること」「買い切りでできること」を 1 行ずつ。本体ブラウザの詐欺対策は報告反映をオンにした時に効くこと（無料のまま）を実物どおりに。§7 の「必ず添える」を入れる。キーワードは「詐欺」「フィッシング」の語を足し、今の広告の語を外しすぎない）
- [ ] **Step 4: 通ることを確かめる** Run: `python3 -m pytest scripts/tests/ -q` → PASS
- [ ] **Step 5**: 文言は Task B4 の画像と一緒に kureho のレビューに出す（全文。決めた事と根拠をまとめて書く）。通るまで採用しない
- [ ] **Step 6: Commit**（レビューを通った版で）

### Task B4: 掲載画像の 1 枚目（詐欺サイト対策）

- [ ] 今の掲載画像の作り（`tasks/screenshot-drafts-v440/`・`scripts/upload_appstore_screenshots.py`）に合わせて 1 枚目を作る。反目標（警告色だらけ・脅し文句）を避け、何をどう止めるかを具体的に。方向が割れる時は違う方向の案を複数作る。kureho のレビューを通るまで採用しない

### Task B5: 同梱の一覧の差し替えと版の準備

**Files:**
- Modify: `Extension/Resources/security-rules.json`・`App/Resources/second-ads-sec.json`・`App/Resources/bundled-rules-info.json`・`project.yml`（版）

- [ ] **Step 1**: `python3 scripts/build_split_rules.py swap-security --second App/Resources/second-ads-sec.json --old-security Extension/Resources/security-rules.json --new-security docs/cdn/security-rules.json --output App/Resources/second-ads-sec.json.new` → 成功なら置き換え、`docs/cdn/security-rules.json` を `Extension/Resources/security-rules.json` へ写す（同梱の広告の部分は変えない）
- [ ] **Step 2**: `bundled-rules-info.json` の `generated_at` を `docs/cdn/version-security.json` の `generated_at` に（ファイルのコメントの決まり）。同梱の `App/Resources/version.json` は広告の一覧の記録（`blocker_list_sha256`・`second_ads_sha256`）で、詐欺の部分の sha は持っていない（2026-11-09 に確認）＝変えない。`Shared/VersionInfo.swift` の読み方がその時も同じかを確かめる
- [ ] **Step 3**: `compile_rules_webkit` を同梱の `security-rules.json`・`second-ads-sec.json` に → 両方 `OK`
- [ ] **Step 4**: Run: `xcodebuild test -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AdblockKeshiTests -quiet` → 0 failure（`BundledRuleListSizeTests` を含む）
- [ ] **Step 5**: 版を上げる（今までの `stage_v44x.py` のやり方）・`release_notes.txt`
- [ ] **Step 6: Commit** `git commit -m "A-218 G1: 同梱の詐欺サイトの一覧を直した選び方の物に"`

### Task B6: 照合表・サポートサイト・宣伝文・提出（🙋 承認）

- [ ] 照合表 `tasks/release-<版>-consistency.md`（今までの形）: 説明文の各行と実物（無料と買い切りの境界・どの拡張とスイッチで効くか）を 1 行ずつ。Task B2 の実機の結果を入れる
- [ ] サポートサイト（`/Users/oharakureho/claude/app-support/src/lib/products.ts` の広告消しの節）は app-support を開いたタブで同じ内容に（deploy は kureho の承認）
- [ ] 宣伝文（審査なしで変えられる）も同じ方向に。外へ出る文面なので全文を示して承認
- [ ] 提出: `submitting-ios-build` skill → 🙋 kureho の承認 → 提出 → 配信後に `auditing-apple-submission` skill

---

## G2 アプリ内広告ブロックに詐欺ドメインを足す

G2 はブランチ `feat/a218-g2-dns-security`（G0 を入れた後の main から）で作る。途中で main に入れても週次の Safari 用は変わらない（DNS 用は CLI の任意の引数で、Safari 用の重要ドメインは `CriticalDomainGuard` だけを読むため）。ワークフローの変更と配信ファイルの push だけは承認の後（Task C7）。

### Task C1: DNS 用の一覧を書き出す（Python）

**Files:**
- Modify: `scripts/build_security_rules.py`
- Test: `scripts/tests/test_build_security_rules.py`

**Interfaces:**
- Consumes: `select_hosts(profile="dns")`（Task A2・A3）
- Produces:
  - `DNS_DEFAULT_LIMIT = 200_000`（Task C6 の実測で決め直す）
  - `write_dns_security(hosts: list[str], txt_path: Path, manifest_path: Path) -> dict` — 本文は**優先順のまま**（並べ替えない＝端末の上限で切っても日本向けが残る）`"\n".join(hosts) + "\n"`。manifest は `{"dns-security_sha256", "dns-security_bytes", "dns-security_count", "generated_at"}`
  - CLI に任意の `--dns-output <txt> --dns-manifest <json> [--dns-limit N]` を足す（無ければ今までどおり Safari 用だけ）

旧版との関係: 旧版は `dns-rules.json`・`version-dns.json` しか読まない＝**旧版には届かない**（旧版はスイッチを読まないので、詐欺の DNS ブロックを渡してはいけない）。`version-dns.json` には足さない（`build_dns_rules.py` が丸ごと書き直すため）。

- [ ] **Step 1: 失敗する試験を書く**
```python
def test_write_dns_security_keeps_priority_order_and_manifest(tmp_path):
    m = write_dns_security(["b.test", "a.test"], tmp_path / "d.txt", tmp_path / "v.json")
    body = (tmp_path / "d.txt").read_bytes()
    assert body == b"b.test\na.test\n"
    assert m["dns-security_count"] == 2 and m["dns-security_bytes"] == len(body)
    assert m["dns-security_sha256"] == hashlib.sha256(body).hexdigest()
    assert json.loads((tmp_path / "v.json").read_text()) == m

def test_dns_output_has_no_ip_or_protected(tmp_path):
    hosts = select_hosts(["1.2.3.4"], ["evil.test", "login.smbc.co.jp"], [], protected={"smbc.co.jp"},
                         shared_parents=set(), jp_tokens=NO_TOKENS, profile="dns", limit=10)
    assert hosts == ["evil.test"]
```
- [ ] **Step 2: 失敗を確かめる** → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 通ることを確かめる** Run: `python3 -m pytest scripts/tests/ -q` → PASS
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: DNS 用の詐欺ドメインの一覧を別ファイルで書き出す"`

### Task C2: 省メモリの集合 `DNSHashedDomainSet`

**Files:**
- Create: `Shared/DNS/DNSHashedDomainSet.swift`・`Tests/DNSHashedDomainSetTests.swift`

**Interfaces:**
- Produces:
  ```swift
  struct DNSHashedDomainSet {
      static let defaultMaxCount: Int          // 初期 200_000（Task C6 で決め直す）
      init(lines: Data, maxCount: Int = DNSHashedDomainSet.defaultMaxCount)
      var count: Int { get }
      func contains(_ domain: String) -> Bool  // 完全一致 + ラベル境界のサフィックス一致（DNSBlocklist と同じ意味）
  }
  ```

持ち方（ここが決め所）: `Set<String>` は 1 件およそ 80 バイト以上で、30 万件だと 25MB 近くになり、作り直しの間は新旧が同時に載る（Network Extension の上限は目安 50MB）。そこで各行を正規化したバイト列のハッシュ（`Hasher`＝プロセスごとに種が変わる SipHash。端末内で作って端末内で照会するだけなので種がずれない）を `[Int]` に入れて並べ替え・重複除去し、照会は二分探索。1 件 8 バイト。データは文字列を作らずにバイトのまま行を切る。正規化: ASCII の大文字を小文字に、行末の `\r`・空白と末尾の `.` を除く、空行と `#` の行は飛ばす、`[a-z0-9._-]` 以外を含む行は捨てる。`maxCount` は**先頭から**数える（ファイルは優先順）。

- [ ] **Step 1: 失敗する試験を書く**
```swift
final class DNSHashedDomainSetTests: XCTestCase {
    private func set(_ s: String, max: Int = 1_000) -> DNSHashedDomainSet { DNSHashedDomainSet(lines: Data(s.utf8), maxCount: max) }

    func test_contains_exactAndSubdomainOnly() {
        let s = set("evil.example\n")
        XCTAssertTrue(s.contains("evil.example"))
        XCTAssertTrue(s.contains("a.b.evil.example"))
        XCTAssertFalse(s.contains("notevil.example"))
        XCTAssertFalse(s.contains("example"))
    }
    func test_normalizes_caseTrailingDotCRLFAndComments() {
        let s = set("# comment\r\nEVIL.Example.\r\n\r\n   \n")
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s.contains("evil.example"))
        XCTAssertTrue(s.contains("WWW.EVIL.EXAMPLE."))
    }
    func test_skipsLinesWithInvalidBytes_andDedupes() {
        let s = set("bad host.example\nok.example\nOK.example\n")
        XCTAssertEqual(s.count, 1)
    }
    func test_maxCount_keepsFirstLines() {
        let s = set("a.example\nb.example\nc.example\n", max: 2)
        XCTAssertTrue(s.contains("a.example")); XCTAssertTrue(s.contains("b.example")); XCTAssertFalse(s.contains("c.example"))
    }
    func test_emptyData_containsNothing() {
        XCTAssertFalse(set("").contains("a.example"))
    }
}
```
- [ ] **Step 2: 失敗を確かめる** Run: `xcodegen generate && xcodebuild test -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AdblockKeshiTests/DNSHashedDomainSetTests -quiet` → コンパイルエラーで FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 通ることを確かめる**（同じコマンド）→ PASS
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: 1 件 8 バイトで持つ DNS 用の詐欺ドメインの集合"`

### Task C3: 判定・重要ドメイン・読み込み

**Files:**
- Modify: `Shared/DNS/DNSEngine.swift`・`Shared/DNS/DNSCriticalGuard.swift`
- Create: `Shared/DNS/DNSSecurityListStore.swift`・`Tests/DNSSecurityListStoreTests.swift`
- Test: `Tests/DNSEngineTests.swift`・`Tests/DNSCriticalGuardTests.swift` に追記

**Interfaces:**
- Consumes: `DNSHashedDomainSet`（Task C2）
- Produces:
  - `DNSEngine.init(blocklist: DNSBlocklist, security: DNSHashedDomainSet? = nil)`（既存の呼び出しはそのまま通る）。判断の順は「重要ドメイン → 広告の一覧 または 詐欺の一覧 → 転送」
  - `struct DNSSecurityListStore { init(appGroupFileURL: URL?, bundleFileURL: URL?); static func shared(appGroupIdentifier: String = "group.com.kureho.adblockkeshi.shared", bundle: Bundle = .main) -> DNSSecurityListStore; func loadData() -> Data? }` — ファイル名 `dns-security.txt`。App Group が空でない時はそれ、無ければ同梱、両方無ければ nil。`Data(contentsOf:options: .alwaysMapped)` で読む
  - `DNSCriticalGuard.dnsSpecific` に足す（DNS だけの守り。`CriticalDomainGuard` はサーバの `critical-list.ts` と揃える決まりなので触らない）:
    `go.jp lg.jp japanpost.jp kuronekoyamato.co.jp sagawa-exp.co.jp jcb.co.jp smbc-card.com vpass.ne.jp saisoncard.co.jp aeon.co.jp rakuten-card.co.jp rakuten-bank.co.jp paypay.ne.jp paypay-bank.co.jp resonabank.co.jp sonybank.net docomo.ne.jp au.com kddi.com softbank.jp ymobile.jp line.me`
    （各ドメインは会社の公式サイトで公式のドメインと確かめてから入れる。確かめられない物は入れずに計画の進捗に書く）

- [ ] **Step 1: 失敗する試験を書く**
```swift
// DNSEngineTests
func test_securityList_blocksListedDomainAndSubdomain() {
    let engine = DNSEngine(blocklist: DNSBlocklist(domains: []), security: DNSHashedDomainSet(lines: Data("evil.example\n".utf8)))
    XCTAssertNotEqual(engine.decide(query: query("x.evil.example")), .forward)
}
func test_securityList_nil_forwards() {
    let engine = DNSEngine(blocklist: DNSBlocklist(domains: []), security: nil)
    XCTAssertEqual(engine.decide(query: query("evil.example")), .forward)
}
func test_critical_beatsSecurityList() {
    let engine = DNSEngine(blocklist: DNSBlocklist(domains: []), security: DNSHashedDomainSet(lines: Data("smbc.co.jp\nnta.go.jp\n".utf8)))
    XCTAssertEqual(engine.decide(query: query("www.smbc.co.jp")), .forward)
    XCTAssertEqual(engine.decide(query: query("www.nta.go.jp")), .forward)
}
// DNSCriticalGuardTests
func test_japaneseBankPaymentDeliveryGovernment_areCritical() {
    for host in ["www.nta.go.jp", "jp-bank.japanpost.jp", "member.kuronekoyamato.co.jp", "www.city.example.lg.jp", "paypay.ne.jp"] {
        XCTAssertTrue(DNSCriticalGuard.isCritical(host), host)
    }
    XCTAssertFalse(DNSCriticalGuard.isCritical("go.jp.evil.example"))
}
// DNSSecurityListStoreTests: App Group が空でない → それ／App Group が空 → 同梱／両方無い → nil
```
（`query(_:)` は既存の DNSEngineTests の作り方に合わせる）
- [ ] **Step 2: 失敗を確かめる** → FAIL
- [ ] **Step 3: 実装する**（新しいファイルの後に `xcodegen generate`）
- [ ] **Step 4: 通ることを確かめる** Run: `xcodebuild test … -only-testing:AdblockKeshiTests -quiet` → 0 failure
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: DNS の判定に詐欺の一覧を足し、日本の銀行・決済・配送・公的機関を守る"`

### Task C4: 配信からの更新（`DNSListUpdater` を名前で使い回す）

**Files:**
- Modify: `Shared/DNS/DNSUpdatePlanner.swift`・`Shared/DNS/DNSListUpdater.swift`・`App/AdblockKeshiApp.swift`
- Test: `Tests/DNSUpdatePlannerTests.swift`・`Tests/DNSListUpdaterTests.swift` に追記

**Interfaces:**
- Produces:
  - `DNSUpdatePlanner.parseManifest(_ data: Data, name: String = "dns-rules") -> Manifest?`（`"<name>_sha256"`・`"<name>_bytes"` を読む。既定は今と同じ）
  - `DNSListUpdater` に `name: String = "dns-rules"` と `validate: (Data) -> Bool = DNSListUpdater.isJSONStringArray` を足す
  - `static func isJSONStringArray(_ data: Data) -> Bool`・`static func isDomainLines(_ data: Data) -> Bool`（空でなく、`[a-z0-9._\-\n\r]` 以外のバイトが無い）
  - `static func sharedSecurity(appGroupIdentifier:session:) -> DNSListUpdater?` — `version-dns-security.json`・`dns-security.txt`・App Group `dns-security.txt`・記録 `applied-dns-security.json`・`name: "dns-security"`・`validate: isDomainLines`
  - `AdblockKeshiApp` の起動時の更新に `sharedSecurity()` を足す。**買い切りの人だけ**（`ProStateStore.sharedAppGroup()?.read().isPro == true`）＝無料の人に数 MB を毎週落とさせない

- [ ] **Step 1: 失敗する試験を書く**: `parseManifest(…, name: "dns-security")` が `dns-security_*` を読み `dns-rules_*` だけの JSON では nil／security の updater が sha 一致で `dns-security.txt` を書き `applied-dns-security.json` を残す／`<html>` のような本文は sha が合っても書かない／既存の試験は変えずに通る
- [ ] **Step 2: 失敗を確かめる** → FAIL
- [ ] **Step 3: 実装する**
- [ ] **Step 4: 通ることを確かめる** → 0 failure
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: DNS の詐欺の一覧を配信から更新する（買い切りの人だけ）"`

### Task C5: トンネルとスイッチの配線

**Files:**
- Create: `Shared/DNS/DNSSecurityToggleSync.swift`・`Tests/DNSSecurityToggleSyncTests.swift`
- Modify: `PacketTunnelExtension/PacketTunnelProvider.swift`・`App/BlockerControlView.swift`・`project.yml`
- Test: `Tests/BlockerControlViewModelTests.swift` に追記

**Interfaces:**
- Consumes: `DNSSecurityListStore`・`DNSHashedDomainSet`・`DNSListUpdater.sharedSecurity`・`StateStore`
- Produces:
  - `enum DNSSecurityToggleSync { static func needsReload(applied: Bool?, stored: Bool, paused: Bool) -> Bool }` — `!paused && applied != nil && applied != stored`。`applied` は**最後の作り直しで求めた値**（一覧が見つかったかではない）。一時停止中に作った素通しのエンジンは `nil`
  - `BlockerControlViewModel.init(…, tunnelReload: @escaping () async -> Void = { await TunnelManager.requestReloadIfRunning() })` — **最後の引数**として足す。保存の直後に呼ぶ（Safari の読み込み直しを待たない）
  - `PacketTunnelProvider`:
    - `reloadEngine()`: 一時停止中は今のまま（素通し・`appliedSecurity = nil`）。それ以外は `let wants = StateStore.sharedAppGroup()?.read().securityEnabled ?? true` を `appliedSecurity` に入れ、`wants` なら `DNSSecurityListStore.shared().loadData()` から `DNSHashedDomainSet` を作って `DNSEngine(blocklist:security:)` に渡す
    - 5 秒ごとの整備で `syncPauseState` の後に `needsReload(applied: appliedSecurity, stored: <state.json の securityEnabled>, paused: pauseDeadline != nil)` なら `reloadEngine()`（通知が落ちても 5 秒以内に揃う）
    - `performSelfFetch()`: 広告の一覧と詐欺の一覧の両方を更新し、どちらかが更新されたら 1 回だけ `reloadEngine()`
  - `project.yml` の `PacketTunnelExtension` に `Shared/StateStore.swift` と `PacketTunnelExtension/Resources/dns-security.txt`（`buildPhase: resources`）を足す

- [ ] **Step 1: 失敗する試験を書く**
```swift
final class DNSSecurityToggleSyncTests: XCTestCase {
    func test_reloadsWhenStoredDiffersFromApplied() {
        XCTAssertTrue(DNSSecurityToggleSync.needsReload(applied: true, stored: false, paused: false))
        XCTAssertTrue(DNSSecurityToggleSync.needsReload(applied: false, stored: true, paused: false))
    }
    func test_noReloadWhenSame_evenIfListWasMissing() {
        XCTAssertFalse(DNSSecurityToggleSync.needsReload(applied: true, stored: true, paused: false))
    }
    func test_noReloadWhilePausedOrPauseEngine() {
        XCTAssertFalse(DNSSecurityToggleSync.needsReload(applied: true, stored: false, paused: true))
        XCTAssertFalse(DNSSecurityToggleSync.needsReload(applied: nil, stored: true, paused: false))
    }
}
// BlockerControlViewModelTests
func test_toggleSecurity_requestsTunnelReloadOnceAfterDebounce() async {
    let reload = expectation(description: "tunnel reload"); reload.assertForOverFulfill = true
    let vm = BlockerControlViewModel(store: store, markPending: { _ in }, reloader: { _ in }, regenerate: {}, tunnelReload: { reload.fulfill() })
    vm.securityEnabled = false; vm.securityEnabled = true; vm.securityEnabled = false
    await fulfillment(of: [reload], timeout: 2.0)
    XCTAssertFalse(store.read().securityEnabled)
}
```
- [ ] **Step 2: 失敗を確かめる** → FAIL
- [ ] **Step 3: 実装する**（新しいファイルの後に `xcodegen generate`。同梱の `dns-security.txt` は C6 の実測までは Task A1 の元データから `--dns-output` で作った物を置く）
- [ ] **Step 4: 通ることを確かめる**: 試験 0 failure ＋ `xcodebuild build -scheme AdblockKeshi -destination 'generic/platform=iOS' -quiet` が通る（拡張のコンパイル）
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: トンネルが詐欺サイトブロックのスイッチに従う（通知が落ちても 5 秒で揃う）"`

### Task C6: メモリの実測で件数を決める（🙋 kureho の手が要る）

**Files:**
- Create: `Shared/DNS/MemoryFootprint.swift`・`Tests/MemoryFootprintTests.swift`
- Modify: `PacketTunnelExtension/PacketTunnelProvider.swift`（`#if DEBUG` だけ）・`Shared/DNS/DNSHashedDomainSet.swift`（`defaultMaxCount`）・`scripts/build_security_rules.py`（`DNS_DEFAULT_LIMIT`）

**Interfaces:**
- Produces: `enum MemoryFootprint { static func current() -> (footprint: UInt64, peak: UInt64)? }`（`task_info(TASK_VM_INFO)` の `phys_footprint`・`ledger_phys_footprint_peak`）。DEBUG のトンネルは作り直しのたびに App Group の `tunnel-memory.json` に `{security_count, ad_count, footprint_mb, peak_mb, at}` を書く（端末の中だけ・外へ送らない）

- [ ] **Step 1: 試験**: `MemoryFootprint.current()` が nil でなく `peak >= footprint > 0` → 実装 → PASS
- [ ] **Step 2**: 元データの DNS 用を上限なし（`--dns-limit 1000000`）で作り、件数 M を記録して同梱に置く。実機（KPhone）へ DEBUG ビルドを入れる
- [ ] **Step 3**: 🙋 kureho: トンネルをオン → 「詐欺サイトブロック」をオフ → オンを 2 回（新旧が同時に載る作り直しを起こす）。Claude は `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.com.kureho.adblockkeshi.shared --source tunnel-memory.json …` で読む（`appGroupDataContainer` は 2026-11-09 に手元の devicectl の help で確認）
- [ ] **Step 4: 件数を決める**（決め方を先に固定）: 詐欺オフの時の最大値を基準 B、オンで M 件の時の最大値を P として、1 件あたり c = (P − B) / M。上限 = `min(floor((25MB − B) / c), M)` を 1 万の位で切り捨て（25MB = 目安 50MB の半分）。`DNSHashedDomainSet.defaultMaxCount` と `DNS_DEFAULT_LIMIT` を同じ値に。結果と計算を `tasks/a218-g2-memory-<日付>.md` に
- [ ] **Step 5: Commit** `git commit -m "A-218 G2: DNS の詐欺の一覧の件数を実機のメモリで決める"`

### Task C7: 実機で他のアプリのリンクが止まるか・配信の準備（🙋）

- [ ] **Step 1**: 確かめ用に、**コミットしない**手元の変更で同梱の `dns-security.txt` の末尾に `example.org` を足した DEBUG ビルドを入れる（App Group に配信の物が無い状態＝同梱が使われる）
- [ ] **Step 2**: 🙋 kureho の実機で、詐欺サイトブロックをオン: LINE（自分宛てのトークの `https://example.org`）・Gmail などのメールアプリ（自分宛てのメール）・標準のメールアプリで開く → 開かない。オフ → 開く。iOS の版・プライベートリレーのオン／オフ・各アプリの版を記録
- [ ] **Step 3**: 止まらなかったアプリは G3 の言葉から外す（spec §6-3）。結果を `tasks/release-<版>-consistency.md` に
- [ ] **Step 4**: 手元の `example.org` を戻す（`git diff` で同梱が C6 の物に戻っていること）
- [ ] **Step 5: ワークフローの変更**（🙋 G2 の提出と一緒に承認）: `build-security-rules.yml` の「Build security-rules.json」に `--dns-output /tmp/dns-security.txt --dns-manifest /tmp/version-dns-security.json --dns-limit <C6 の値>` を足し、コピーと `git add` に `docs/cdn/dns-security.txt docs/cdn/version-dns-security.json` を足す（`timeout-minutes: 30` はそのまま）。最新の元データで `docs/cdn/` と同梱の `dns-security.txt` を作り直す
- [ ] **Step 6: DNS 用の計測**: `security_list_report.py --profile dns --old none --new docs/cdn/dns-security.txt …` を回し、誤ブロック 0・IPv4 0・日本向けの見本の数を `tasks/a218-g2-memory-*.md` に足す（Safari 用とは別に出す・spec §6-1）
- [ ] **Step 7: 全試験** Run: `python3 -m pytest scripts/tests/ -q` と `xcodebuild test … -only-testing:AdblockKeshiTests -quiet` → 0 failure
- [ ] **Step 8: Commit** `git commit -m "A-218 G2: 週次で DNS 用の詐欺の一覧も配信する"`（push は承認の後）

---

## G3 看板の第 2 弾

### Task D1: 「他のアプリで開いたリンクも止める（買い切り）」を足す

- [ ] Task C7 で止まったアプリの範囲だけで、副題（叩き台「アプリ内の詐欺リンクも止める」の方向）・説明文・掲載画像・サポートサイトに足す。§7 の決まり・`test_store_metadata_wording.py` を通す。LINE などの他社名は名前・副題・キーワードに入れない（説明文で書けるかは 5.2.5 の範囲を確かめてから）
- [ ] 購入画面（`App/Pro/PaywallView.swift`）と ASC の課金項目の説明が新しい掲載と食い違っていないかを照合表で確かめ、食い違う所は kureho のレビューに出す（spec は購入画面の変更を決めていない）
- [ ] G2 の版と一緒に照合表・kureho のレビュー → 🙋 提出の承認（G2 の配信ファイル・ワークフローの変更・提出を 1 回にまとめて見せてよい）→ 配信後に `auditing-apple-submission`
