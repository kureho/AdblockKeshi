import KurehoKit
import SwiftUI

/// 設定カードの「詳しく見る →」から出す購入シート。
///
/// ★**他 21 本と挙動をそろえるための包み**（2026-09-18 kureho「ボタン押下後の挙動が他と違う」）。
///   ❌ 設定カードの CTA を `NavigationLink` にして設定画面へ push する
///   → ✅ **シートで購入画面を出す**（全アプリ共通: `showingPaywall = true` → `.sheet { … }`）
///   → 理由: 他アプリの CTA は必ずシートで購入画面が出る。このアプリだけ画面遷移だったので、
///     同じカードを押しても返ってくるものが違った（memory `feedback_plus_upgrade_card_pattern`）。
///
/// 標準の作法は 4 つ。どれも他アプリの購入シートと同じ:
///   ① `NavigationStack` で包んでタイトルを出す
///   ② **右上**に「閉じる」を置く（2026-09-18 に 22 本で統一。`.cancellationAction` は
///      左上に出るので使わない＝広告消しだけ左上のままだった）
///   ③ 買えたら自動で閉じる（買った直後に同じ購入画面が残っていると「買えたのか」が分からない）
///   ④ **中身の高さぴったりで開く**（`fittingSheetHeight`）。既定の全画面だと、短い訴求の下に
///      意味のない空白が残る（kureho「このモーダル長すぎこんなに長い必要ないでしょ」）
struct ProPaywallSheet: View {
    let store: ProStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PaywallView(store: store)
                .navigationTitle("アプリ内広告ブロック")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("閉じる") { dismiss() }
                            .accessibilityIdentifier("paywallSheetClose")
                    }
                }
                // 購入・復元のどちらで権利が付いても閉じる。
                .onChange(of: store.isPro) { _, isPro in
                    if isPro { dismiss() }
                }
        }
        .fittingSheetHeight()
    }
}
