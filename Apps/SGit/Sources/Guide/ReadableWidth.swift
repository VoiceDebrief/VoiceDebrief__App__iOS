import SwiftUI
import UIKit

extension View {
    /// A comfortable reading width on an iPad or a Mac, as in VoiceDebrief.
    func readableWidth(_ width: CGFloat = 720) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemGroupedBackground))
    }
}
