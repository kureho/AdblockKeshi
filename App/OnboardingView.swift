import SwiftUI
import AVKit

struct OnboardingView: View {
    let onReady: () -> Void

    @State private var player: AVPlayer = makePlayer()

    var body: some View {
        VStack(spacing: 24) {
            VideoPlayer(player: player)
                .aspectRatio(3.0/4.0, contentMode: .fit)
                .padding(.horizontal)
                .onAppear {
                    player.play()
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: player.currentItem,
                        queue: .main
                    ) { _ in
                        player.seek(to: .zero)
                        player.play()
                    }
                }

            Button(action: onReady) {
                Text("準備する")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .cornerRadius(12)
                    .padding(.horizontal)
            }

            NavigationLink("ライセンス情報") {
                AboutView()
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.top, 4)
        }
        .padding(.vertical)
    }

    private static func makePlayer() -> AVPlayer {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let resource = (lang == "ja") ? "onboarding-ja" : "onboarding-en"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "mp4") else {
            return AVPlayer()
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        return player
    }
}
