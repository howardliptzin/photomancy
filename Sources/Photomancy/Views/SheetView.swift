import SwiftUI
import AppKit
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
                    // One handler, reading the modifiers itself.
                    //
                    // Attaching a separate `.modifiers(.command)` gesture does
                    // not work here: a plain `onTapGesture` fires for a modified
                    // click as well, so both would run and the order between
                    // them is not ours to decide. Branching on the flags keeps
                    // the whole convention in one readable place.
                    .onTapGesture {
                        hasKeyboardFocus = true
                        controller.click(cell: item.cell, modifiers: NSEvent.modifierFlags)
                    }
                }

                // Shown whenever something is selected, not only while this
                // view holds the keyboard: selection is what Delete acts on, so
                // it has to outlast the click that made it.
                ForEach(controller.selectedCells.sorted().filter(cells.indices.contains), id: \.self) { selected in
                    let cell = cells[selected]
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
        .onKeyPress(.leftArrow) { controller.moveSelection(byColumns: -1, rows: 0); return .handled }
        .onKeyPress(.rightArrow) { controller.moveSelection(byColumns: 1, rows: 0); return .handled }
        .onKeyPress(.upArrow) { controller.moveSelection(byColumns: 0, rows: -1); return .handled }
        .onKeyPress(.downArrow) { controller.moveSelection(byColumns: 0, rows: 1); return .handled }
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
