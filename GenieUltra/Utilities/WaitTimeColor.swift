import SwiftUI

enum WaitTimeColor {
    static func color(for waitTime: Int?) -> Color {
        guard let waitTime else { return .gray }
        switch waitTime {
        case 0...20: return .green
        case 21...45: return .yellow
        case 46...75: return .orange
        default: return .red
        }
    }
}
