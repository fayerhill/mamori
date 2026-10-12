import AppKit
import SwiftUI

enum Theme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let foreground = Color.primary
    static let secondary = Color.secondary
    static let accent = Color.accentColor
    static let warning = Color.orange
    static let stopAccent = Color.red
    static let width: CGFloat = 280
    static let height: CGFloat = 290
}

struct Hairline: View {
    var body: some View { Divider() }
}
