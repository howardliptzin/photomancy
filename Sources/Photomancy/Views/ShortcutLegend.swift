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
        ("P", "Pin or unpin the selected photograph"),
        ("Click", "Select a photograph"),
        ("⌘ Click", "Add one to the selection, or take it out"),
        ("⇧ Click", "Select everything from the last one to here"),
        ("⌥ Click", "Pin or unpin, in place"),
        ("Drag", "Move to a cell and pin it there"),
        ("Double-click", "Open it in the lightbox"),
        ("↩", "Open or close the lightbox"),
        ("← →", "In the lightbox: the previous or next photograph"),
        ("⌫", "Remove the selected photograph from this collection"),
        ("⌘⌫", "Delete it from Photomancy"),
        ("⌃⌘N", "Move the selection to a new collection"),
        ("⇧⌘R", "Rename the collection"),
        ("⌘Z", "Step back through arrangements"),
        ("⇧⌘Z", "Step forward again"),
        ("⌘P", "Print"),
        ("?", "Show this"),
        ("Esc", "Close this, or the lightbox"),
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
