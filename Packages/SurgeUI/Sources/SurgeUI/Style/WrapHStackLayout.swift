import SwiftUI

/// Lays subviews out in a row and wraps to a new line when the next one does not fit.
/// Chips use it so no workspace filter is ever hidden behind a horizontal scroll.
struct WrapHStackLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var cursor: CGFloat = 0
        var lineTop: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widestLine: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor > 0 && cursor + size.width > maxWidth {
                lineTop += lineHeight + lineSpacing
                cursor = 0
                lineHeight = 0
            }
            cursor += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widestLine = max(widestLine, cursor - spacing)
        }

        return CGSize(width: proposal.width ?? widestLine, height: lineTop + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var cursor = bounds.minX
        var lineTop = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor > bounds.minX && cursor + size.width > bounds.maxX {
                cursor = bounds.minX
                lineTop += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: cursor, y: lineTop),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            cursor += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
