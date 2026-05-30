# AdblockKeshi プロジェクト指示

## プロダクト
- iOS Safari Content Blocker、買い切り ¥400、シンプル極限訴求
- ターゲット: 「アドブロック」という言葉を知らない、Safari をもっと快適に使いたい層
- spec: `~/claude/docs/superpowers/specs/2026-05-30-adblock-design.md`

## 開発ルール
- Swift 5.10 / SwiftUI / iOS 17 SDK
- XcodeGen で project.yml 管理（.xcodeproj は git ignore）
- bundle id (app): com.kureho.adblockkeshi
- bundle id (extension): com.kureho.adblockkeshi.blocker
- App Group: group.com.kureho.adblockkeshi.shared
- Team ID: L455WPL8QZ

## やらないこと（spec §3 参照）
- カスタムフィルタ追加
- ホワイトリスト機能
- ブロック統計表示
- 通知・更新案内

## 関連メモリ
- `feedback_simulator_no_activate.md` — シミュレータ操作時 activate 禁止
- `feedback_pricing_metadata_strict.md` — App Store メタデータ価格表記禁止
- `reference_x_promo_stillcam_proven.md` — X¥1,500プロモ CPI¥3-4実証
