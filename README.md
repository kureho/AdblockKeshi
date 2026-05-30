# 広告消し (AdblockKeshi)

iOS Safari Content Blocker。「アドブロック」を知らない層向けのシンプル極限プロダクト。

- spec: `~/claude/docs/superpowers/specs/2026-05-30-adblock-design.md`
- plan: `~/claude/docs/superpowers/plans/2026-05-30-adblock-keshi-plan-a-mvp.md`

## ビルド

```bash
xcodegen generate
open AdblockKeshi.xcodeproj
```

## テスト

```bash
xcodebuild test -project AdblockKeshi.xcodeproj -scheme AdblockKeshi \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```
