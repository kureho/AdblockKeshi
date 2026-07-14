import NetworkExtension

/// DNS トンネル本体（ローカル VPN・split tunnel で DNS のみ捕捉）。
/// ★NetworkExtension 依存＝シミュレータでは動作しない（ビルドは通る・ランタイムは実機のみ）。
/// パケット判定は純関数（PacketCodec / DNSEngine / DNSBlocklist…）に委譲し、ここは I/O 配線に徹する。
/// startTunnel / packetFlow ループ / 上流転送は Task 13・14 で実装する。
final class PacketTunnelProvider: NEPacketTunnelProvider {

    override func startTunnel(options: [String: NSObject]?,
                             completionHandler: @escaping (Error?) -> Void) {
        completionHandler(nil)   // stub（Task 13 で実装）
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
