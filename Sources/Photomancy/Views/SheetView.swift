import SwiftUI
import PhotomancyCore

extension Color {
    /// The shared value, drawn. Core carries the components; each renderer makes
    /// its own colour type from them, in sRGB, so screen and paper agree.
    init(_ sheet: SheetColor) {
        self.init(.sRGB, red: sheet.red, green: sheet.green, blue: sheet.blue, opacity: sheet.alpha)
    }
}

/// The sheet: a true rows × columns grid, positioned from `layout()`.
///
/// Deliberately not a `LazyVGrid`. Its geometry would be invisible to the print
/// path and the two would drift apart, which surfaces as "it didn't print the
/// way it looked". Every rectangle here is one the print path will be handed
/// unchanged in M5.
struct SheetView: View {

    @Environment(LibraryController.self) private var controller

    @FocusState private var hasKeyboardFocus: Bool

    private var settings: SheetSettings { controller.settings }

    var body: some View {
        GeometryReader { proxy in
            let cells = layout(
                cols: settings.columns,
                rows: settings.rows,
                gap: settings.gap,
                cellAspect: controller.cellAspect,
                canvas: proxy.size
            )

            ZStack(alignment: .topLeading) {
                // The canvas is the window, so the whole area is the sheet —
                // including the dead space at the two edges that do not bind.
                Color(settings.background)
                    .onTapGesture { hasKeyboardFocus = true }

                // Iterating the photographs that are placed, keyed by
                // photograph, is what lets a frame *move* to its new cell when
                // the sheet is rolled rather than cross-fading in place. The
                // movement is how the eye registers what changed.
                ForEach(placed(in: cells.count), id: \.reference.id) { item in
                    SheetCell(
                        reference: item.reference,
                        size: cells[item.cell].size,
                        background: settings.background,
                        isPinned: controller.arrangement.isPinned(cell: item.cell)
                    )
                    .frame(width: cells[item.cell].width, height: cells[item.cell].height)
                    .position(x: cells[item.cell].midX, y: cells[item.cell].midY)
                    // Click selects. Pinning is Option-click or P.
                    //
                    // This reverses the brief's original inversion, and for a
                    // better reason than the one it replaces: selection is the
                    // prerequisite for everything else you can do to one
                    // photograph — open it, remove it — so the plainest gesture
                    // has to mean "this one", not "hold this one".
                    .onTapGesture {
                        hasKeyboardFocus = true
                        controller.focusedCell = item.cell
                    }
                    .simultaneousGesture(
                        TapGesture().modifiers(.option).onEnded {
                            hasKeyboardFocus = true
                            controller.focusedCell = item.cell
                            controller.togglePin(at: item.cell)
                        }
                    )
                }

                if hasKeyboardFocus, cells.indices.contains(controller.focusedCell) {
                    let cell = cells[controller.focusedCell]
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color(settings.background.contrastingInk).opacity(0.55), lineWidth: 2)
                        .frame(width: cell.width + 6, height: cell.height + 6)
                        .position(x: cell.midX, y: cell.midY)
                        .allowsHitTesting(false)
                }
            }
        }
        .focusable()
        .focused($hasKeyboardFocus)
        .focusEffectDisabled()
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.leftArrow) { controller.moveFocus(byColumns: -1, rows: 0); return .handled }
        .onKeyPress(.rightArrow) { controller.moveFocus(byColumns: 1, rows: 0); return .handled }
        .onKeyPress(.upArrow) { controller.moveFocus(byColumns: 0, rows: -1); return .handled }
        .onKeyPress(.downArrow) { controller.moveFocus(byColumns: 0, rows: 1); return .handled }
        .onKeyPress(.escape) {
            guard controller.showingShortcuts else { return .ignored }
            controller.showingShortcuts = false
            return .handled
        }
        .overlay {
            if controller.showingShortcuts {
                ShortcutLegend { controller.showingShortcuts = false }
            }
        }
    }

    private struct Placement {
        let cell: Int
        let reference: PhotoReference
    }

    private func placed(in cellCount: Int) -> [Placement] {
        controller.arrangement.slots.prefix(cellCount).enumerated().compactMap { cell, id in
            guard let id, let reference = controller.reference(for: id) else { return nil }
            return Placement(cell: cell, reference: reference)
        }
    }
}
