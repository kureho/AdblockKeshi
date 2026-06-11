import StoreKit
import SwiftUI
import UIKit

/// 満足度カードの表示状態を ReviewPrompt エンジンと UI の間で仲介する。
@MainActor
@Observable
final class ReviewPromptCoordinator {
    static let shared = ReviewPromptCoordinator()
    var showSatisfactionPrompt = false
    #if DEBUG
    /// シミュレータ確認用: 実績数の表示を上書き（リリースビルドには存在しない）
    var debugCountOverride: Int?
    #endif
}

/// 満足度確認カード（中央カード型・背景暗転）。ふるさと納税帳で確立した情緒版の移植。
///
/// 設計意図 (MannerCamera4K/docs/superpowers/specs/2026-06-11-review-prompt-v2-design.md §2.1):
/// - 「レビュー」「星」「評価」という語を使わない満足度アンケート。
///   独自 UI でのレビュー依頼 (Guidelines 5.6.1) に該当させないための核心ルール。
/// - 「気に入っています」→ 公式 `AppStore.requestReview(in:)`（表示可否は OS が決める）
/// - 「改善してほしい」→ サポートフォーム（不満の受け皿）
/// - 「あとで」→ 閉じるだけ。機能制限なし (3.2.2(x) 遵守)
struct SatisfactionPromptView: View {
    let onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconBounced = false
    @State private var bubbleShown = false

    /// 吹き出しの背景（アプリのアクセント色 = システムブルーを薄く敷く）
    private var bubbleColor: Color { Color.accentColor.opacity(0.12) }
    /// 吹き出し文字（地と同系のアクセント色 = tinted スタイル）
    private var bubbleTextColor: Color { Color(red: 0.13, green: 0.30, blue: 0.62) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                // 吹き出し: アプリアイコンが感謝を喋る構図 (gratitude-first)
                VStack(spacing: 0) {
                    Text(thanksText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(bubbleTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    BubbleTail()
                        .fill(bubbleColor)
                        .frame(width: 12, height: 7)
                }
                .scaleEffect(bubbleShown || reduceMotion ? 1.0 : 0.85)
                .opacity(bubbleShown || reduceMotion ? 1.0 : 0.0)
                .onAppear {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75).delay(0.12)) {
                        bubbleShown = true
                    }
                }
                .padding(.bottom, -8)

                // アプリアイコン実画像（kureho 指定）。取得できない環境ではシールドにフォールバック
                Group {
                    if let icon = Self.appIconImage {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 14.3))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14.3)
                                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .accessibilityHidden(true)
                // 出現時にひと弾み (350ms・1回だけ・NN/g 100-400ms 帯)。Reduce Motion 時は弾まない
                .scaleEffect(iconBounced || reduceMotion ? 1.0 : 0.8)
                .onAppear {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        iconBounced = true
                    }
                }

                Text("学習する広告消しは\nお役に立っていますか？")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button {
                        onDismiss()
                        requestSystemReview()
                    } label: {
                        Text("気に入っています")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDismiss()
                        SupportLink.openContact()
                    } label: {
                        Text("改善してほしい")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(bubbleTextColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("サポートページを開きます"))

                    Button {
                        onDismiss()
                    } label: {
                        Text("あとで")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 300)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
            .padding(.horizontal, 40)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(named: Text("あとで")) { onDismiss() }
        }
    }

    /// 表示用の実績数。永続化済みの報告履歴件数（端末ローカル DB 相当）を正とし、
    /// 取得失敗/0件時のみエンジンカウンタにフォールバック
    private var usageCount: Int {
        #if DEBUG
        if let override = ReviewPromptCoordinator.shared.debugCountOverride { return override }
        #endif
        // エンジンカウンタ = ブロッカー有効で使った日数（1日1回 bump）そのもの
        return ReviewPrompt.successCount()
    }

    /// 利用実績に応じた感謝のひとこと。使い込んでいる人には実績そのもので語りかける
    private var thanksText: String {
        let count = usageCount
        if count >= 20 {
            return "これまで \(count)日間のご利用、\nありがとうございます！"
        } else {
            return "使っていただけてうれしいです\nありがとうございます！"
        }
    }

    /// Info.plist の CFBundleIcons からプライマリアイコンを取得（asset catalog 名直書きより堅牢）
    static var appIconImage: UIImage? {
        guard let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let last = files.last else { return nil }
        return UIImage(named: last)
    }

    private func requestSystemReview() {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        {
            AppStore.requestReview(in: scene)
        }
    }
}

/// 吹き出しの下向きしっぽ
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: rect.width, y: 0))
        p.addLine(to: CGPoint(x: rect.width / 2, y: rect.height))
        p.closeSubpath()
        return p
    }
}

#Preview {
    SatisfactionPromptView(onDismiss: {})
        .preferredColorScheme(.light)
}
