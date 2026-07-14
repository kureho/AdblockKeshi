# 広告消し v4.0（フリーミアム転換 + DNS 型アプリ内広告ブロック）実装計画

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 広告消しを「本体無料 + Pro 買い切り ¥800（DNS 型アプリ内広告ブロック）」へ転換し、既存購入者を恒久 Pro で救済しつつ、月販の蓋（有料バッジ）を外して収益を再起動する。

**Architecture:** ローカル VPN 型（NEPacketTunnelProvider）で DNS(port 53) のみを sentinel IP に向け、端末内で広告ドメインを判定 → block 時は合成応答・非 block 時は固定 public DNS(1.1.1.1) へ転送。ブロック判定・パケット処理は NetworkExtension 非依存の純関数（DNSEngine / PacketCodec / DNSCriticalGuard）に切り出し TDD する。Pro 状態は StoreKit 2 + AppTransaction.originalAppVersion の grandfather 判定で決め、App Group 経由で extension と共有。

**Tech Stack:** Swift 5.10 / SwiftUI / NetworkExtension(NEPacketTunnelProvider) / StoreKit 2(AppTransaction) / XcodeGen / XCTest / 既存 App Group `group.com.kureho.adblockkeshi.shared` / 既存 GitHub Pages CDN。

**Spec:** `AdblockKeshi/docs/superpowers/specs/2026-07-14-v4-freemium-dns-design.md`（r3）
**調査正典（grandfather・転換手順の詳細はこちらを参照）:** `AdblockKeshi/tasks/v4-freemium-dns-plan.md`

## 全タスク共通の注記（着手前に必読・plan レビュー r1 反映）

- **ファイルを新規作成/削除したら必ず `xcodegen generate` を実行してからテスト**。`.xcodeproj` は git ignore の生成物で sources はディレクトリ指定のため、再生成しないと新規ファイルがターゲットに入らず「テストが見つからない」別種エラーになる（Task 1 実装時に実証済み）。
- **NEPacketTunnelProvider（Network Extension provider）は iOS シミュレータで動作しない = 実機必須**（Apple 公式既知制約）。tunnel の「起動する/connected になる」完了条件は**すべて実機**。シミュレータで確認できるのは「ビルド通過」「UI 画面遷移」「純関数のユニットテスト」まで。
- **テスト可能性の鉄則**: ユニットテストする型は `Shared/`（特に `Shared/DNS/`）に置く。`AdblockKeshiTests` は本体アプリを TEST_HOST にするため、`PacketTunnelExtension/` 配下の型は `@testable import AdblockKeshi` から見えずコンパイルエラーになる。extension ターゲット固有ファイルはグルーのみに留める。
- **DEBUG 限定 Pro オーバーライド**（起動引数 or UserDefaults）を Task 17 で用意する。シミュレータは AppTransaction 不可のため、これが無いと Chunk 5 の UI 開発で Pro ゲートの先に入れない。

---

## ファイル構造（新規/変更）

**新規: DNS コア（NetworkExtension 非依存の純関数・TDD の主戦場）**
- `Shared/DNS/DNSMessage.swift` — DNS メッセージの parse/encode（ヘッダ・question・回答合成）
- `Shared/DNS/DNSEngine.swift` — domain 抽出 → 照合 → block 応答合成 or 転送指示（純関数）
- `Shared/DNS/DNSCriticalGuard.swift` — DNS 版 CriticalDomainGuard（github.io 追加・既存 CriticalDomainGuard から移植）
- `Shared/DNS/DNSBlocklist.swift` — ドメイン Set（完全一致 + サフィックス一致）・上限縮退
- `Shared/DNS/PacketCodec.swift` — IPv4/IPv6 + UDP（+ TCP 最小 parse/RST 合成）decode/encode・checksum

**新規: DNS リスト・転送・記録（Shared/DNS・テスト可能に集約 / plan レビュー C-3・I-5）**
- `Shared/DNS/BlocklistStore.swift` — App Group 読込 + フォールバック（**Shared に置く=テスト可能**）
- `Shared/DNS/DNSForwardingTable.swift` — 上流転送の対応表（キー=リライト後 DNS ID 単独 → 元 request ParsedPacket・insert/resolve/contains/expireAll・純関数）
- `Shared/DNS/DNSUpdatePlanner.swift` — self-fetch の更新要否判定（既存 RuleUpdatePlanner 同型・純関数）

**新規: DNS ブロックリスト本体（プロダクトの価値・plan レビュー C-2）**
- `PacketTunnelExtension/Resources/dns-rules.json` — bundle 同梱の初期 curated リスト
- `scripts/build_dns_rules.py`（or 既存 scripts 拡張）— curated ドメイン → dns-rules payload + `version-dns.json` manifest 生成
- CDN 配信（既存 GitHub Pages・実体 `docs/cdn/` = kureho.github.io/AdblockKeshi/cdn/）に version-dns.json + payload を追加

**新規: tunnel extension（薄いグルー・I/O のみ）**
- `PacketTunnelExtension/PacketTunnelProvider.swift` — NEPacketTunnelProvider 本体（sentinel 設定・packetFlow ループ・上流 I/O・純関数を呼ぶだけ）

**新規: Pro / 課金（本体アプリ）**
- `App/Pro/ProStore.swift` — grandfather 判定 + StoreKit 2 購入/復元 + Pro 状態の単一真実源
- `App/Pro/ProEntitlementCache.swift` — 恒久キャッシュ（UserDefaults + Keychain）
- `App/Pro/GrandfatherPolicy.swift` — 閾値判定（純関数・Int 比較・environment 分岐）
- `App/Pro/ProStateStore.swift` — Pro 状態を App Group へ atomic 書出（StateStore パターン）

**新規: DNS 設定 UI（本体アプリ・Pro ゲート）**
- `App/DNS/DNSSettingsView.swift` — ワンタップ有効化・NEVPNStatusDidChange 監視・限界明記
- `App/DNS/TunnelManager.swift` — NETunnelProviderManager のラッパ
- `App/Pro/PaywallView.swift` — 購入/復元 UI（Pro でも到達可能・ロード失敗明示）

**変更:**
- `project.yml` — PacketTunnelExtension ターゲット追加（app + extension に packet-tunnel-provider entitlement・App Group）
- `App/AboutView.swift`（または設定画面）— 復元導線 + Pro 状態表示 + DEBUG 診断
- fastlane/metadata（別チャンク）・app-support LP（別リポ・別チャンク）

---

## Chunk 1: DNS コア純関数（PacketCodec + DNSMessage）

このチャンクは NetworkExtension に一切依存しない。全て `AdblockKeshiTests` でユニットテストする。

### Task 1: PacketCodec — IPv4/UDP のパース ✅ 完了（commit fcd8d6d）

**Files:**
- Create: `Shared/DNS/PacketCodec.swift`
- Test: `Tests/PacketCodecTests.swift`

実装済み（RED→GREEN 2テスト PASS）。makeIPv4UDP ヘルパは Step 1 でテストファイルに同梱済み（M-1 反映）。以下は記録:

- [x] **Step 1: 失敗するテストを書く**

```swift
import XCTest
@testable import AdblockKeshi

final class PacketCodecTests: XCTestCase {
    // 最小の IPv4+UDP パケット（src 10.0.0.1:5353 → dst 198.18.0.1:53・payload 3バイト）を
    // 手組みし、PacketCodec がヘッダを正しく分解できることを固定する。
    func test_parseIPv4UDP_extractsPortsAndPayload() throws {
        let payload = Data([0xAA, 0xBB, 0xCC])
        let packet = Self.makeIPv4UDP(
            src: (10,0,0,1), srcPort: 5353,
            dst: (198,18,0,1), dstPort: 53, payload: payload)
        let parsed = try XCTUnwrap(PacketCodec.parse(packet))
        XCTAssertEqual(parsed.version, .v4)
        XCTAssertEqual(parsed.proto, .udp)
        XCTAssertEqual(parsed.srcPort, 5353)
        XCTAssertEqual(parsed.dstPort, 53)
        XCTAssertEqual(parsed.payload, payload)
    }
}
```

（`makeIPv4UDP` ヘルパは Step 1 でテストファイルに同梱済み。IHL=5・total length・UDP length を正しく詰める）

- [ ] **Step 2: 失敗を確認**

Run: `xcodebuild test -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AdblockKeshiTests/PacketCodecTests/test_parseIPv4UDP_extractsPortsAndPayload`
Expected: FAIL（`PacketCodec` 未定義でコンパイルエラー）

- [ ] **Step 3: 最小実装**

`PacketCodec.parse(_:)` を実装。IPv4 ヘッダ（version/IHL/protocol/src/dst）→ UDP ヘッダ（srcPort/dstPort/length）→ payload を切り出す `ParsedPacket` を返す。パース不能は nil（fail-open の起点）。IPv6・TCP は後続 Task で追加するので、この Task では IPv4/UDP のみ対応・それ以外は nil。

- [ ] **Step 4: パス確認**

Run: 同上
Expected: PASS

- [ ] **Step 5: commit**

```bash
git add Shared/DNS/PacketCodec.swift Tests/PacketCodecTests.swift
git commit -m "feat(dns): PacketCodec で IPv4/UDP パケットをパース（TDD）"
```

### Task 2: PacketCodec — IPv4/UDP の応答パケット組み立て（checksum 含む）✅ 完了（commit e2a988e）

**Files:**
- Modify: `Shared/DNS/PacketCodec.swift`
- Test: `Tests/PacketCodecTests.swift`

- [ ] **Step 1: 失敗するテスト**

```swift
// 受信パケットの src/dst を入れ替え、新 payload で応答パケットを組み立てる。
// round-trip: 組み立てた応答を再度 parse すると src/dst ポートが入れ替わっていること + payload 一致。
func test_buildResponse_swapsEndpointsAndSetsPayload() throws {
    let req = try XCTUnwrap(PacketCodec.parse(Self.makeIPv4UDP(
        src: (10,0,0,1), srcPort: 5353, dst: (198,18,0,1), dstPort: 53,
        payload: Data([0x01]))))
    let respPayload = Data([0x09, 0x08])
    let respPacket = PacketCodec.buildResponse(to: req, payload: respPayload)
    let parsed = try XCTUnwrap(PacketCodec.parse(respPacket))
    XCTAssertEqual(parsed.srcPort, 53)      // 応答の src は元の dst
    XCTAssertEqual(parsed.dstPort, 5353)    // 応答の dst は元の src
    XCTAssertEqual(parsed.payload, respPayload)
}
```

- [ ] **Step 2: 失敗確認** — Run: `-only-testing:AdblockKeshiTests/PacketCodecTests/test_buildResponse_swapsEndpointsAndSetsPayload` / Expected: FAIL
- [ ] **Step 3: 実装** — `buildResponse(to:payload:)`。IPv4 ヘッダ（total length 再計算・header checksum 再計算）+ UDP ヘッダ（length・checksum。IPv4 UDP checksum は 0 許容なので v1 は 0 でも可だが、正しく計算する）を組む。
- [ ] **Step 4: パス確認** — Run: 同上 / Expected: PASS
- [ ] **Step 5: commit** — `git commit -m "feat(dns): PacketCodec で UDP 応答パケットを合成（endpoint swap + checksum）"`

### Task 3: PacketCodec — IPv6/UDP 対応

**Files:** Modify `Shared/DNS/PacketCodec.swift` / Test `Tests/PacketCodecTests.swift`

- [ ] **Step 1: 失敗するテスト**（IPv6+UDP の parse と buildResponse の round-trip。IPv6 は擬似ヘッダ checksum が必須なので UDP checksum を検証する）
- [ ] **Step 2: 失敗確認**
- [ ] **Step 3: 実装**（IPv6 ヘッダ 40 バイト固定・next header=17=UDP・UDP checksum は IPv6 擬似ヘッダで計算）
- [ ] **Step 4: パス確認**
- [ ] **Step 5: commit** — `git commit -m "feat(dns): PacketCodec で IPv6/UDP に対応"`

### Task 4: PacketCodec — TCP:53 の最小 parse + RST 合成（fail-open 層2）

**Files:** Modify `Shared/DNS/PacketCodec.swift` / Test `Tests/PacketCodecTests.swift`

spec §fail-open 層2（案A）: TCP:53 は userspace shim を作らず RST 即応答で fail-fast する。

- [ ] **Step 1: 失敗するテスト**

```swift
// TCP SYN(dst 53) を parse できること + それに対する RST 応答を合成できること。
func test_tcpSyn_parseAndBuildRST() throws {
    let syn = Self.makeIPv4TCPSyn(src: (10,0,0,1), srcPort: 40000, dst: (198,18,0,1), dstPort: 53, seq: 1000)
    let parsed = try XCTUnwrap(PacketCodec.parse(syn))
    XCTAssertEqual(parsed.proto, .tcp)
    XCTAssertEqual(parsed.dstPort, 53)
    let rst = try XCTUnwrap(PacketCodec.buildTCPRST(to: parsed))
    let prst = try XCTUnwrap(PacketCodec.parse(rst))
    XCTAssertEqual(prst.proto, .tcp)
    XCTAssertTrue(prst.tcpFlags.contains(.rst))
    XCTAssertEqual(prst.srcPort, 53)   // RST の src は元 dst
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（TCP ヘッダの最小 parse = ports/seq/flags のみ。RST 合成 = ACK=SYN.seq+1・RST|ACK フラグ・TCP checksum 計算）→ パス確認 → commit `git commit -m "feat(dns): TCP:53 の最小 parse と RST 合成（fail-fast・案A）"`

---

## Chunk 2: DNSMessage + DNSEngine + Blocklist + Guard（判定コア）

### Task 5: DNSMessage — question からドメイン名を抽出

**Files:** Create `Shared/DNS/DNSMessage.swift` / Test `Tests/DNSMessageTests.swift`

- [ ] **Step 1: 失敗するテスト**

```swift
func test_parseQuestion_extractsQNameAndType() throws {
    // "ads.example.com" A クエリの DNS メッセージを手組み
    let msg = Self.makeQuery(qname: "ads.example.com", qtype: 1) // 1 = A
    let parsed = try XCTUnwrap(DNSMessage.parseQuery(msg))
    XCTAssertEqual(parsed.qname, "ads.example.com")
    XCTAssertEqual(parsed.qtype, 1)
    XCTAssertEqual(parsed.id, Self.expectedID)
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（DNS ヘッダ 12 バイト + QNAME のラベル列 decode + QTYPE/QCLASS。圧縮ポインタはクエリでは通常不要だが来たら nil で fail-open）→ パス → commit `git commit -m "feat(dns): DNSMessage でクエリの qname/qtype を抽出（TDD）"`

### Task 6: DNSMessage — block 応答の合成（qtype 別）

**Files:** Modify `Shared/DNS/DNSMessage.swift` / Test `Tests/DNSMessageTests.swift`

spec §応答合成: A→0.0.0.0 / AAAA→:: / HTTPS(65)・SVCB(64)→NODATA / その他→NODATA。

- [ ] **Step 1: 失敗するテスト**（A クエリに対し 0.0.0.0 を answer に持つ応答 / AAAA に対し :: / type65 に対し NODATA=answer 0・SOA 省略可 の3ケース。応答は元 id を保持・QR=1・qd をコピー）
- [ ] **Step 2〜5**: 失敗確認 → 実装 → パス → commit `git commit -m "feat(dns): block 応答を qtype 別に合成（A/AAAA/NODATA）"`

### Task 7: DNSBlocklist — 完全一致 + サフィックス一致 + 上限縮退

**Files:** Create `Shared/DNS/DNSBlocklist.swift` / Test `Tests/DNSBlocklistTests.swift`

- [ ] **Step 1: 失敗するテスト**

```swift
func test_matches_exactAndSuffix_butNotSubstring() {
    let list = DNSBlocklist(domains: ["ads.example.com", "doubleclick.net"])
    XCTAssertTrue(list.isBlocked("ads.example.com"))       // 完全一致
    XCTAssertTrue(list.isBlocked("x.doubleclick.net"))     // サフィックス一致
    XCTAssertFalse(list.isBlocked("notdoubleclick.net"))   // 部分文字列は不一致
    XCTAssertFalse(list.isBlocked("example.com"))          // 上位ドメインは不一致
}

func test_capsToLimit_whenOverMemoryBudget() {
    let many = (0..<100).map { "d\($0).example.com" }
    let list = DNSBlocklist(domains: many, maxCount: 10)
    XCTAssertEqual(list.count, 10)  // 上限で縮退（メモリ上限対策）
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（Set<String> 完全一致 + ラベル境界のサフィックス走査。maxCount 縮退）→ パス → commit `git commit -m "feat(dns): DNSBlocklist の完全/サフィックス一致と上限縮退（TDD）"`

### Task 8: DNSCriticalGuard — 保護ドメインは絶対にブロックしない（fail-open 層3）

**Files:** Create `Shared/DNS/DNSCriticalGuard.swift` / Test `Tests/DNSCriticalGuardTests.swift`

既存 `Shared/CriticalDomainGuard.swift` を移植し、**self-fetch 先 `github.io` を追加**（spec §self-fetch 自己生存保証）。

- [ ] **Step 1: 失敗するテスト**

```swift
func test_criticalDomains_neverBlocked_includingGithubIO() {
    XCTAssertTrue(DNSCriticalGuard.isCritical("push.apple.com"))
    XCTAssertTrue(DNSCriticalGuard.isCritical("kureho.github.io")) // self-fetch 先（自己更新経路を守る）
    XCTAssertTrue(DNSCriticalGuard.isCritical("api.example.github.io"))
    XCTAssertFalse(DNSCriticalGuard.isCritical("ads.example.com"))
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（既存 criticalDomains に `github.io` 追加・isCritical のサフィックス判定は既存踏襲）→ パス → commit `git commit -m "feat(dns): DNSCriticalGuard 移植 + github.io（self-fetch 保護）"`

### Task 9: DNSEngine — 全経路を束ねる純関数（fail-open 層1）

**Files:** Create `Shared/DNS/DNSEngine.swift` / Test `Tests/DNSEngineTests.swift`

- [ ] **Step 1: 失敗するテスト**

```swift
// DNSEngine.decide(query:) は「素通し(forward) / ブロック応答(respond)」を返す純関数。
func test_decide_blocksListed_forwardsOthers_protectsCritical_failsOpen() throws {
    let blocklist = DNSBlocklist(domains: ["ads.example.com"])
    let engine = DNSEngine(blocklist: blocklist)

    // ブロック対象 → respond（0.0.0.0）
    let blocked = engine.decide(query: Self.query("ads.example.com", type: 1))
    guard case .respond(let data) = blocked else { return XCTFail("should block") }
    XCTAssertTrue(Self.answerIsZeroIP(data))

    // 非対象 → forward
    if case .forward = engine.decide(query: Self.query("example.com", type: 1)) {} else { XCTFail("should forward") }

    // critical はリストにあっても forward（層3）
    let g = DNSEngine(blocklist: DNSBlocklist(domains: ["push.apple.com"]))
    if case .forward = g.decide(query: Self.query("push.apple.com", type: 1)) {} else { XCTFail("critical must forward") }

    // パース不能 → forward（層1 fail-open）
    if case .forward = engine.decideRaw(Data([0x00])) {} else { XCTFail("unparsable must forward") }
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（decide: critical 判定 → blocklist 判定 → respond/forward。decideRaw: DNSMessage.parseQuery 失敗時は forward）→ パス → commit `git commit -m "feat(dns): DNSEngine で判定を集約（block/forward・fail-open 3層）"`

### Task 9.5: DNSForwardingTable — 上流転送の対応表（純関数・plan レビュー I-5）

**Files:** Create `Shared/DNS/DNSForwardingTable.swift` / Test `Tests/DNSForwardingTableTests.swift`

上流(1.1.1.1)へ転送したクエリの応答を、正しい元クライアントに配送するための対応表。**キーはリライト後 DNS transaction ID 単独**（Task 13 で確定した r3 設計。上流は共有 NWConnection で応答に srcPort が載らないため、転送前に DNS ID をユニーク値へリライトし、そのリライト後 ID をキーに元 request を引く。srcPort による衝突回避ではなく ID 一意化で衝突を構造的に消す）。値 = 元 request の ParsedPacket（srcIP/srcPort/元 DNS ID を保持）。tunnel の I/O から切り離せる純ロジック。

- [ ] **Step 1: 失敗するテスト**（insert(rewrittenID, request) → resolve(rewrittenID) で元 request 取得・1回で消費 / contains(rewrittenID) で使用中判定（ID 割り当てが未使用値を選ぶため）/ expireAll(olderThan:) で古いエントリ掃除 / 別 rewrittenID が独立）
- [ ] **Step 2〜5**: 失敗確認 → 実装（[UInt16: Entry] + タイムスタンプ・resolve は remove して返す）→ パス → commit `git commit -m "feat(dns): DNSForwardingTable で上流応答の突合（リライト後 ID キー・TDD）"`

### Task 10: Chunk 1-2 の全ユニットテスト green 確認

- [ ] **Step 1**: Run: `xcodegen generate && xcodebuild test -scheme AdblockKeshi -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:AdblockKeshiTests -quiet`
      Expected: 既存 121+ テスト + 新規 DNS テストすべて PASS（回帰ゼロ）
- [ ] **Step 2**: Codex レビュー — `codex review --commit HEAD`（DNS コアの純関数群を対象）。指摘は次チャンク前に解消

### Task 10.5: DNS curated ブロックリスト初版 + CDN 生成 + bundle 同梱（plan レビュー C-2）

**Files:** Create `PacketTunnelExtension/Resources/dns-rules.json` / `scripts/build_dns_rules.py` / CDN 生成物 / Modify `project.yml`（bundle 同梱）

DNS リストはプロダクトの価値そのもの。ここが無いと E2E（AdMob 搭載アプリでバナー消滅確認）に進めない。

- [ ] **Step 1**: curated ドメイン初版を作る（既存 popunder 研究の広告配信網ドメイン + 主要広告 SDK ドメイン = AdMob `googleads.g.doubleclick.net`/`pagead2.googlesyndication.com` 等・自作 AdMob アプリで実測しながら）。外部リスト取込時は `docs/license-audit` 運用（GPL 不可）
- [ ] **Step 2**: `scripts/build_dns_rules.py` = curated → `dns-rules.json`（JSON array of domains）+ `version-dns.json`（manifest・sha256）。RuleUpdater の manifest パターン踏襲
- [ ] **Step 3**: `dns-rules.json` を PacketTunnelExtension の bundle resources に同梱（project.yml・fresh install で App Group 空でも初期リストが読める＝Content Blocker bundle 同梱教訓と同型）
- [ ] **Step 4**: CDN（既存 GitHub Pages `cdn/`）に version-dns.json + payload 配置
- [ ] **Step 5: commit** — `git commit -m "feat(dns): curated DNS リスト初版 + 生成 script + bundle 同梱 + CDN 配信"`

---

## Chunk 3: PacketTunnelExtension（新ターゲット + tunnel 本体）

このチャンクで初めて NetworkExtension に触れる。extension は「純関数を呼ぶ薄いグルー」に徹する。

### Task 11: project.yml に PacketTunnelExtension ターゲットを追加

**Files:**
- Modify: `project.yml`（tunnel ターゲット + **bundle 同梱 `PacketTunnelExtension/Resources/dns-rules.json`**・**Safari CB 2拡張（ContentBlocker/Popunder）から `excludes: [DNS]` を確定**=メモリ制約対策 M-2）
- Create: `PacketTunnelExtension/Info.plist`
- Create: `PacketTunnelExtension/PacketTunnelExtension.entitlements`
- Modify: `App/App.entitlements`（**既存ファイル**・M-4。packet-tunnel array を追記。App Group/keychain は既存）

- [ ] **Step 1: ターゲット定義を追加**

`project.yml` の targets に追記（既存 ContentBlockerExtension のパターン踏襲）:
```yaml
  PacketTunnelExtension:
    type: app-extension
    platform: iOS
    sources:
      - path: PacketTunnelExtension
      - path: Shared/DNS          # 純関数コアを共有
    info:
      path: PacketTunnelExtension/Info.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.networkextension.packet-tunnel
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).PacketTunnelProvider
        CFBundleDisplayName: アプリ内広告ブロック
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.kureho.adblockkeshi.tunnel
        CODE_SIGN_ENTITLEMENTS: PacketTunnelExtension/PacketTunnelExtension.entitlements
        PRODUCT_NAME: PacketTunnelExtension
```
AdblockKeshi の dependencies に `- target: PacketTunnelExtension` / `embed: true` を追加。

- [ ] **Step 2: entitlements 2ファイル**

`PacketTunnelExtension/PacketTunnelExtension.entitlements`:
```xml
<key>com.apple.developer.networking.networkextension</key>
<array><string>packet-tunnel-provider</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.com.kureho.adblockkeshi.shared</string></array>
```
`App/App.entitlements` にも同じ `packet-tunnel-provider` array を追加（本体が NETunnelProviderManager で構成保存するため）。App Group は既存にあるはず。

- [ ] **Step 3: xcodegen で生成できることを確認**

Run: `xcodegen generate` → Expected: エラーなし。`xcodebuild -list -project AdblockKeshi.xcodeproj` に PacketTunnelExtension スキーム or ターゲットが出る。

- [ ] **Step 4: 空の PacketTunnelProvider スタブでビルド通過**

`PacketTunnelExtension/PacketTunnelProvider.swift` を最小スタブ（`class PacketTunnelProvider: NEPacketTunnelProvider { override func startTunnel(...) { completionHandler(nil) } }`）で作成し、`xcodebuild build -scheme AdblockKeshi` が通ることを確認。

- [ ] **Step 5: commit**
```bash
git add project.yml PacketTunnelExtension App/App.entitlements
git commit -m "feat(tunnel): PacketTunnelExtension ターゲット追加 + entitlements（ビルド通過スタブ）"
```

**注記**: Apple Developer Portal で App ID に Network Extension capability の有効化、Provisioning Profile の再生成が必要（kureho 操作 or 自動署名）。この Task の実機/archive 段階で `-allowProvisioningUpdates` を使う。

### Task 12: BlocklistStore — App Group からリスト読込（+ フォールバック）

**Files:** Create `Shared/DNS/BlocklistStore.swift`（**Shared に置く=テスト可能・C-3**）/ Test `Tests/BlocklistStoreTests.swift`

- [ ] **Step 1: 失敗するテスト**（App Group の dns-rules.json → 無ければ bundle 同梱初期リスト → 無ければ空、の順でロード。空でも DNSEngine は fail-open で forward するので安全。App Group container は DI で差し替えテスト＝StateStore の `init(stateFileURL:)` パターン踏襲）
- [ ] **Step 2〜5**: 失敗確認 → 実装（StateStore と同じ atomic 読込・JSON array of domains を DNSBlocklist に。bundle フォールバックは Bundle 注入で test 可能に）→ パス → commit `git commit -m "feat(dns): BlocklistStore の App Group 読込 + フォールバック（Shared・TDD）"`

### Task 12.7: DNSUpdatePlanner — self-fetch の更新要否判定（純関数・I-5）

**Files:** Create `Shared/DNS/DNSUpdatePlanner.swift` / Test `Tests/DNSUpdatePlannerTests.swift`

既存 `RuleUpdatePlanner`（`Tests/RuleUpdatePlannerTests.swift` あり）と同型。「手元 version-dns の sha256 と CDN manifest を比較 → 更新要否」を純関数で。tunnel の I/O から分離。

- [ ] **Step 1〜5**: RED（同 sha なら skip・差分なら fetch 対象を返す）→ 実装 → GREEN → commit `git commit -m "feat(dns): DNSUpdatePlanner で self-fetch 更新要否を判定（純関数・TDD）"`

### Task 13: PacketTunnelProvider — sentinel 設定 + packetFlow ループ（実機検証）

**Files:** Modify `PacketTunnelExtension/PacketTunnelProvider.swift`（NetworkExtension 依存 = **シミュレータ不可・実機必須**。純関数は Task 1-9.5 で TDD 済みなので、ここは I/O 配線のみ）

- [ ] **Step 1: 非 Pro なら起動拒否（I-3）**: startTunnel 冒頭で App Group の Pro 状態（ProStateStore）を読み、**非 Pro なら `completionHandler(NEVPNError(...))` で起動拒否**（設定アプリ VPN 画面からの直接 ON も塞ぐ・返金 edge も起動時再検証で反映）
- [ ] **Step 2: startTunnel の network settings**:
  - `NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")`
  - **tunnel 自身のアドレス割当（必須・I-4）**: `let v4 = NEIPv4Settings(addresses: ["198.18.0.2"], subnetMasks: ["255.255.255.0"])` / `let v6 = NEIPv6Settings(addresses: ["fd00::2"], networkPrefixLengths: [64])`
  - `v4.includedRoutes = [NEIPv4Route(destinationAddress: "198.18.0.1", subnetMask: "255.255.255.255")]`（sentinel /32 のみ）/ v6 も sentinel /128
  - `dnsSettings = NEDNSSettings(servers: ["198.18.0.1", "fd00::1"])`・`dnsSettings.matchDomains = [""]`（全 DNS を tunnel へ）
  - sentinel は 198.18.0.0/15（RFC 2544 予約）から
  - `setTunnelNetworkSettings` 完了後に readPackets ループ開始
- [ ] **Step 3: パケット処理ループ**
  - `packetFlow.readPackets { packets, protocols in ... }`
  - `PacketCodec.parse` → dstPort==53 判定
    - UDP:53 → `DNSEngine.decideRaw(payload)` → `.respond` なら `PacketCodec.buildResponse` を writePackets / `.forward` なら **DNSForwardingTable に登録**して上流へ送信
    - TCP:53 → `PacketCodec.buildTCPRST` を writePackets（fail-fast）
  - ループ再帰
- [ ] **Step 4: 上流転送 I/O（I/O モデル確定・plan レビュー r2 Important）**
  - 上流 = **1.1.1.1 と 2606:4700:4700::1111 の両方（IPv6-only/NAT64 網対応）**。
  - ★誤配送回避★: 上流応答には DNS ID しか載らず srcPort を復元できないため、**転送前に DNS ID を tunnel 内でユニーク値へリライト**し、DNSForwardingTable のキー（リライト後 ID → 元 srcPort/元 ID/元 IP）で突合 → 応答時に元 ID へ戻して `buildResponse`。別クライアントの同一 ID 衝突を構造的に消す（クライアント単位 NWConnection 分離でも可だが ID リライトの方が接続数を抑えられる）。
  - 応答受信時に `DNSForwardingTable.resolve(rewrittenID)` で元クライアントを引く。5s タイムアウトで `expireAll`（応答なしは偽装せず捨てる）
  - **Task 9.5 の DNSForwardingTable のキーは「リライト後 DNS ID」単独**（srcPort はリライトで一意化されるため値に保持）→ Task 9.5 のテストもこの形に合わせる
- [ ] **Step 5: 実機スモーク（明示ゲート・C-1/M-5）**: 実機で tunnel が connected になり、通常ブラウジングが壊れず、既知広告ドメインが 0.0.0.0 で返ることを確認（Safari で `nslookup` 相当・Charles 不要な範囲で）。E2E フルは spec §5（Task 20 ではない）
- [ ] **Step 6: commit** — `git commit -m "feat(tunnel): sentinel DNS tunnel + packetFlow + 上流 v4/v6 + 非Pro起動拒否"`

### Task 14: self-fetch + sendProviderMessage reload

**Files:** Modify `PacketTunnelExtension/PacketTunnelProvider.swift` / 使用: `Shared/DNS/DNSUpdatePlanner.swift`（Task 12.7・純関数は済）

- [ ] **Step 1: tunnel 内日次 self-fetch**（DNSUpdatePlanner で要否判定 → version-dns.json 取得 → dns-rules.json 更新 → BlocklistStore reload。github.io は DNSCriticalGuard 保護済みで自己更新経路は死なない）
- [ ] **Step 2: 二重 DL 回避**: app 側 RuleUpdater(dns variant・Task 14.5) と tunnel self-fetch が同じ version-dns を見るので、適用記録（applied-dns.json・DNSUpdatePlanner が参照）を App Group で共有
- [ ] **Step 3: `handleAppMessage`（sendProviderMessage）で app からの即時 reload を受ける**
- [ ] **Step 4: commit** — `git commit -m "feat(tunnel): DNS リストの日次 self-fetch + app 即時 reload"`

### Task 14.5: app 側の DNS リスト更新（RuleUpdater dns variant・C-2 の書き手2箇所）

**Files:** Modify `Shared/RuleUpdater.swift` / Test `Tests/RuleUpdaterTests.swift`

spec「書き手2箇所」の app 側。既存 RuleUpdater（基本保護の CDN 更新）に dns variant を追加し、アプリ起動時/BGTask でも DNS リストを更新（tunnel が起動していない間の鮮度維持）。

- [ ] **Step 1〜5**: RED（既存 RuleUpdaterTests パターンで dns variant の manifest 比較・適用）→ 実装 → GREEN → commit `git commit -m "feat(dns): RuleUpdater に dns variant を追加（app 側の DNS リスト更新）"`

---

## Chunk 4: Pro / grandfather / 課金（本体アプリ）

grandfather の全チェックリストは `tasks/v4-freemium-dns-plan.md §grandfather` を正とする。ここは実装 Task に落とす。

### Task 15: GrandfatherPolicy — 閾値判定（純関数・TDD）

**Files:** Create `App/Pro/GrandfatherPolicy.swift` / Test `Tests/GrandfatherPolicyTests.swift`

- [ ] **Step 1: 失敗するテスト**

```swift
func test_isLegacy_intComparison_notString_andEnvironmentGated() {
    let p = GrandfatherPolicy(conversionBuild: 10000, cutoffDate: Self.date("2026-07-01"))
    // 文字列比較なら "99" < "10000" が false になるバグを固定で防ぐ: build 99 は legacy
    XCTAssertTrue(p.isLegacy(originalBuild: "99", originalPurchaseDate: nil, environment: .production))
    XCTAssertTrue(p.isLegacy(originalBuild: "27", originalPurchaseDate: nil, environment: .production))
    XCTAssertFalse(p.isLegacy(originalBuild: "10000", originalPurchaseDate: nil, environment: .production))
    XCTAssertFalse(p.isLegacy(originalBuild: "10001", originalPurchaseDate: nil, environment: .production))
    // 審査/sandbox 環境（"1.0"）では常に false（購入導線を審査員に見せる）
    XCTAssertFalse(p.isLegacy(originalBuild: "1", originalPurchaseDate: nil, environment: .sandbox))
    // originalBuild 欠落でも purchaseDate が cutoff 以前なら legacy（補助判定・古い購入の救済）
    XCTAssertTrue(p.isLegacy(originalBuild: nil, originalPurchaseDate: Self.date("2026-06-01"), environment: .production))
}
```

- [ ] **Step 2〜5**: 失敗確認 → 実装（Int 変換比較・environment==.production 限定・build 欠落時 purchaseDate < cutoff 補助）→ パス → commit `git commit -m "feat(pro): GrandfatherPolicy 閾値判定（Int比較・env gate・date補助・TDD）"`

**M-3 注記**: `originalBuild: nil` の定義は「AppTransaction が欠落 or originalAppVersion が Int にパースできない（"1.0" 形式等）」。`cutoffDate` は**転換当日（無料化実行日時）に確定**させる運用（早すぎる定数だと窓の購入者を date 補助が拾えない。ただし build<10000 の主判定が拾うため実害は限定的）。

**取りこぼしケースのフォールバック（Chunk 0 廃止の代償・許容範囲）**: 「v4.0 を一度も起動せず旧版削除→v4.0 新規インストール」した既存購入者は、もし Apple が再インストールで originalAppVersion を書き換える仕様なら救えない（頻度極小）。この端末には (a) 復元ボタン（過去購入の有無を Transaction で確認）、(b) Paywall/設定に「以前ご購入の方でうまく反映されない場合はお問い合わせ」導線、で対応。実害は本体無料+基本保護は使えて Pro(¥800)のみ。実挙動はリリース後に自然に判明する（困る人が出たら個別救済）。

### Task 15.5: ローカル `.storekit` に Pro 非消耗型を定義（I-2・Task 17 の前提）

**Files:** Create `AdblockKeshi.storekit`（リポジトリに現存しない・新規）/ Modify `project.yml`（test target resources に追加）

- [ ] **Step 1**: `.storekit` に非消耗型 `com.kureho.adblockkeshi.pro`（¥800）を定義
- [ ] **Step 2**: `project.yml` の `AdblockKeshiTests` に `.storekit` を resources 追加 + scheme の test config に storeKitConfiguration 指定（`SKTestSession(configurationFileNamed:)` 用）。iOS 18.3 sim 実 PASS 手法 = reference_storekittest_cli_workaround
- [ ] **Step 3: commit** — `git commit -m "feat(pro): ローカル .storekit に Pro 非消耗型を定義（StoreKitTest 用）"`
- **注**: ASC 上の IAP 作成は Chunk 6 の提出フェーズ（初回 IAP はバージョン同時提出が必須）

### Task 16: ProEntitlementCache — 恒久キャッシュ（剥奪しない）

**Files:** Create `App/Pro/ProEntitlementCache.swift` / Test `Tests/ProEntitlementCacheTests.swift`

★Chunk 0 廃止に伴う中核（2026-07-15 kureho 承認）: **iCloud KVS を恒久レールに加える**ことで「再インストール時の originalAppVersion 挙動」の不確実性を実測なしで吸収する。v4.0 に一度でもアップデートした端末は originalAppVersion で判定 → iCloud KVS へ書込 → 以後の削除・機種変でも Apple ID 経由で復元（iCloud 有効端末）。

- [ ] **Step 1: 失敗するテスト**（一度 grandfather=true を書いたら、以後 read が false/失敗でも true を返す＝剥奪しない。**UserDefaults + Keychain + NSUbiquitousKeyValueStore(iCloud KVS) の3冗長**。read は「どれか1つでも true なら true」）
- [ ] **Step 2〜5**: 失敗確認 → 実装（既存 `App/Storage/KeychainHelper.swift` + iCloud KVS の DI 可能なラッパ。iCloud OFF 端末では KVS 不在＝UserDefaults/Keychain にフォールバック）→ パス → commit `git commit -m "feat(pro): ProEntitlementCache を3冗長で恒久化（iCloud KVS で再インストール耐性）"`

### Task 17: ProStore — StoreKit 2 購入/復元 + Pro 判定の統合

**Files:** Create `App/Pro/ProStore.swift` / `App/Pro/ProStateStore.swift` / Test `Tests/ProStoreTests.swift`（StoreKitTest 使用）

- [ ] **Step 1: 失敗するテスト**（`.storekit` config で 非消耗型「pro」を定義 → 購入で Pro=true / grandfather=true でも Pro=true / `Transaction.currentEntitlements` 反映。iOS 18.3 sim 実 PASS 手法 = reference_storekittest_cli_workaround）
- [ ] **Step 2〜5**: 失敗確認 → 実装:
  - `ProStore`: 起動時 `AppTransaction.shared`（タイムアウト付き）→ GrandfatherPolicy 判定 → cache 反映。`refresh()` は復元ボタン起点のみ。Pro = grandfather OR currentEntitlements。
  - `ProStateStore`: Pro 状態を App Group state に atomic 書出（StateStore パターン）→ tunnel が起動時に読む
  - **DEBUG 限定 Pro オーバーライド（I-7）**: 起動引数 `-FORCE_PRO` or UserDefaults で Pro=true を強制（`#if DEBUG` のみ）。シミュレータは AppTransaction 不可なので、これが無いと Chunk 5 の UI（Pro ゲート先）を開発できない
  → パス → commit `git commit -m "feat(pro): ProStore で購入/復元/grandfather を統合 + DEBUG Pro override"`

---

## Chunk 5: DNS 設定 UI + Paywall + 診断（本体アプリ）

### Task 19: TunnelManager + DNSSettingsView + PaywallView

**Files:** Create `App/DNS/TunnelManager.swift` / `App/DNS/DNSSettingsView.swift` / `App/Pro/PaywallView.swift`（UI は手動/スナップショット検証中心）

- [ ] **Step 1: TunnelManager**（`NETunnelProviderManager.loadAllFromPreferences` → 無ければ生成・保存 → `startVPNTunnel`。`NEVPNStatusDidChange` を Combine/NotificationCenter で購読し status を publish）
- [ ] **Step 2: DNSSettingsView**（Pro ゲート: 非 Pro は PaywallView へ / Pro はワンタップ ON-OFF トグル + status 表示 + 説明画面（他 VPN 排他・再起動後は手動 ON・YouTube 等は消えない・上流 Cloudflare の明記））
- [ ] **Step 3: PaywallView**（購入ボタン + **復元ボタン（Pro 状態でも常に到達可能）** + 商品ロード中/失敗の明示 UI + リトライ。2026-01 reject 対策）
- [ ] **Step 4: 既存導線に接続**（`App/ContentView.swift` or `AboutView.swift` に「アプリ内広告ブロック」セクション追加）
- [ ] **Step 5: シミュレータ目視（購入フロー + 画面遷移まで）**（StoreKitTest config で購入→トグル出現→説明画面表示を確認・スクショ。**tunnel の実起動は実機のみ = Task 13 Step 5 の実機スモークでカバー・C-1**）
- [ ] **Step 6: commit** — `git commit -m "feat(ui): DNS 設定 UI + Paywall（復元常設・限界明記・Pro ゲート）"`

---

## Chunk 6: metadata / LP / 転換リリース

転換リリースの全手順は `tasks/v4-freemium-dns-plan.md §転換リリース手順` を正とする。

### Task 21: metadata 刷新

**Files:** `fastlane/metadata/ja/*`

- [ ] keywords: 「アプリ 広告」「アプリ内 広告」系の無人語を追加（100字/バイト検証）
- [ ] description: 訴求「他アプリの広告も**抑える**」+ 限界明記（YouTube 等不可）+ 規約/プライバシーポリシーのリンク追加（QReate reject 対策）+ 「本体無料 + Pro 買い切り」再フレーミング
- [ ] subtitle/promotional_text/keywords/screenshots に価格・無料表記を書かない（2.3.7）
- [ ] commit

### Task 22: LP・外部の価格表記スイープ（app-support リポ）

**Files:** `app-support/src/lib/products.ts` の adblockkeshi エントリ + privacy ページ

- [ ] 「¥500」「アプリ内課金もなし」「Plus は無し」「price: ¥500（構造化データ）」等、Pro IAP で虚偽になる断定文言を全スイープ（2.3.1 false price）
- [ ] privacy ページに DNS/VPN のローカル処理 + 上流 Cloudflare の記述追加
- [ ] **本番デプロイは転換リリースと同期**（承認後・価格無料化と同じタイミング）
- [ ] commit

### Task 23: 転換ビルドの採番 + 提出

**Files:** `project.yml`（CURRENT_PROJECT_VERSION を 10000 へジャンプ・MARKETING_VERSION 4.0.0）

- [ ] CFBundleVersion 履歴一覧化（過去リリースの build 番号確認）→ 転換ビルドを 10000 へ（cutoffDate = 提出時に確定・M-3）
- [ ] ASC で非消耗型 IAP「Pro」¥800 作成（初回 IAP・バージョン同時提出）
- [ ] **ASC Web UI で IAP を 4.0.0 バージョンに紐付け + IAP 審査用スクショ添付（I-8・MosaicBlur 教訓: first IAP は API では版に attach されず Web UI 必須）**
- [ ] submitting-ios-build skill で Phase 1-5 → **手動リリース**・Phased Release オフ・評価リセット禁止・審査ノート（転換説明の実績文例）
- [ ] 4点監査

### Task 23.5: E2E ゲート実行（提出前必須・spec §5 の明示タスク）

- [ ] grandfather の実機確認（アップデート経由で Pro 維持・iCloud 復元）/ 実機で tunnel connected + 通常ブラウジング無破壊 / 対象3アプリでバナー消滅目視（tunnel OFF→ON スクショ比較）/ YouTube 広告が消えない（ネガティブコントロール・限界明記と整合）/ 主要20サイト + 決済系 無破壊 / 他 VPN 排他・スリープ/機内モード復帰
- [ ] 全項目 PASS を提出可否ゲートにする（1つでも NG なら Chunk 6 提出に進まない）

### Task 24: 承認後の転換実行（窓管理）

- [ ] 承認後: **即時価格変更で無料化 → 実機で ¥0 確認 → 分単位でリリース**（深夜帯）
- [ ] 同時に app-support LP デプロイ
- [ ] リリース後: 新規/旧購入者の両判定を実機確認 + 数日レビュー監視（「Pro が消えた」→復元案内）
- [ ] auditing-apple-submission で4点監査

---

## 実装順序と依存

Chunk 1-2（DNS 純関数・完全 TDD・依存なし）→ Chunk 4（Pro・純関数 TDD 中心・Chunk 1-2 と並行可・**grandfather は iCloud KVS 恒久化で実測不要**）→ Chunk 3（tunnel・実機必須・Chunk 1-2/4 の純関数と Pro 状態に依存）→ Chunk 5（UI・Chunk 3,4 に依存）→ Chunk 6（転換リリース・全部が揃ってから）。

**クリティカルパス**: 純関数（Chunk 1-2, 4 の大半）は今すぐ並行で片付く。**kureho 依存の律速は Chunk 3 の tunnel 実機検証と Chunk 6 の審査/転換のみ**（Chunk 0 廃止で診断リリースの審査待ちが消えた）。

各チャンク末に Codex レビュー（codex-default-review）。提出前に E2E ゲート（spec §5）全項目。
