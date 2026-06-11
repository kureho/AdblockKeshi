import StoreKit
import SwiftUI
import UIKit

/// 満足度カードの表示状態を ReviewPrompt エンジンと UI の間で仲介する。
@MainActor
@Observable
final class ReviewPromptCoordinator {
    static let shared = ReviewPromptCoordinator()
    var showSatisfactionPrompt = false
}

/// 満足度確認カード（中央カード型・背景暗転）。StillCam 4K で確立したパターンの移植。
///
/// 設計意図 (MannerCamera4K/docs/superpowers/specs/2026-06-11-review-prompt-v2-design.md §2.1):
/// - 「レビュー」「星」「評価」という語を使わない満足度アンケート。
///   独自 UI でのレビュー依頼 (Guidelines 5.6.1) に該当させないための核心ルール。
/// - 「気に入っています」→ 公式 `AppStore.requestReview(in:)`（表示可否は OS が決める）
/// - 「改善してほしい」→ サポートフォーム（不満の受け皿）
/// - 「あとで」→ 閉じるだけ。機能制限なし (3.2.2(x) 遵守)
struct SatisfactionPromptView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                // アプリアイコン実画像（kureho 指定）。取得できない環境ではシールドにフォールバック
                Group {
                    if let icon = Self.appIconImage {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 13.5))
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(.green)
                    }
                }
                .accessibilityHidden(true)

                Text("学習する広告消しはお役に立っていますか？")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    Button {
                        onDismiss()
                        requestSystemReview()
                    } label: {
                        Text("気に入っています")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDismiss()
                        SupportLink.openContact()
                    } label: {
                        Text("改善してほしい")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color(uiColor: .systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
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
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(uiColor: .separator), lineWidth: 0.5)
            )
            .padding(.horizontal, 40)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(named: Text("あとで")) { onDismiss() }
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

#Preview {
    SatisfactionPromptView(onDismiss: {})
        .preferredColorScheme(.light)
}
