import SwiftUI
import AppKit

/// Invisible strips along the window edges that resize the panel with
/// native resize cursors, in place of a dedicated grabber.
struct ResizeEdges: View {
    @Binding var width: Double
    @Binding var height: Double
    let minSize: CGSize
    let maxSize: CGSize

    @State private var startSize: CGSize?

    private static let edgeGrip: CGFloat = 6
    private static let cornerGrip: CGFloat = 14

    var body: some View {
        Color.clear
            .overlay(alignment: .leading) {
                handle(dx: -1, dy: 0, cursor: .resizeLeftRight)
                    .frame(width: Self.edgeGrip)
                    .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .trailing) {
                handle(dx: 1, dy: 0, cursor: .resizeLeftRight)
                    .frame(width: Self.edgeGrip)
                    .frame(maxHeight: .infinity)
            }
            .overlay(alignment: .bottom) {
                handle(dx: 0, dy: 1, cursor: .resizeUpDown)
                    .frame(height: Self.edgeGrip)
                    .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottomLeading) {
                handle(dx: -1, dy: 1, cursor: Self.diagonalCursor(bottomRight: false))
                    .frame(width: Self.cornerGrip, height: Self.cornerGrip)
            }
            .overlay(alignment: .bottomTrailing) {
                handle(dx: 1, dy: 1, cursor: Self.diagonalCursor(bottomRight: true))
                    .frame(width: Self.cornerGrip, height: Self.cornerGrip)
            }
    }

    private func handle(dx: CGFloat, dy: CGFloat, cursor: NSCursor) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    cursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        cursor.set()
                        let start = startSize ?? CGSize(width: width, height: height)
                        startSize = start
                        if dx != 0 {
                            width = min(max(minSize.width, start.width + dx * value.translation.width), maxSize.width)
                        }
                        if dy != 0 {
                            height = min(max(minSize.height, start.height + dy * value.translation.height), maxSize.height)
                        }
                    }
                    .onEnded { _ in startSize = nil }
            )
    }

    private static func diagonalCursor(bottomRight: Bool) -> NSCursor {
        if #available(macOS 15.0, *) {
            return .frameResize(position: bottomRight ? .bottomRight : .bottomLeft, directions: .all)
        }
        return .crosshair
    }
}
