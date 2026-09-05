import SwiftUI

/// The `?` overlay.
///
/// Every action is also a menu item showing its key equivalent — that is the
/// native baseline and the menu bar needs it regardless. This exists because the
/// loop is a full-window activity and nobody is looking at the menu bar while
/// they are in it. A keyboard route nobody can find is not a keyboard route.
struct ShortcutLegend: View {

    let dismiss: () -> Void

    private let shortcuts: [(key: String, action: String)] = [
        ("Space", "Randomize"),
        ("← → ↑ ↓", "Move between cells"),
        ("P", "Pin or unpin the focused photograph"),
        ("Click", "Pin or unpin, in place"),
        ("⌘Z", "Step back through arrangements"),
        ("⇧⌘Z", "Step forward again"),
        ("⌘P", "Print"),
        ("?", "Show this"),
        ("Esc", "Close this"),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 12) {
                Text("Keyboard")
                    .font(.headline)

                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    ForEach(shortcuts, id: \.key) { shortcut in
                        GridRow {
                            Text(shortcut.key)
                                .font(.system(.callout, design: .monospaced))
                                .gridColumnAlignment(.leading)
                            Text(shortcut.action)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 24, y: 8)
        }
        .transition(.opacity)
    }
}
