import Foundation

enum WatchFormatters {
    static func elapsedText(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        let m = total / 60
        let s = total % 60
        let tenths = Int((elapsed - Double(total)) * 10)
        return String(format: "%02d:%02d.%01d", m, s, tenths)
    }
}