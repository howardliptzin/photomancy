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

    /// A drag in progress. Nothing is committed until the photograph is dropped,
    /// so a drag abandoned in the margin leaves no step in the history.
    @State private var drag: Drag?

    private struct Drag: Equatable {
        /// Captured once, when the drag begins — the preview renumbers cells
        /// under the pointer, and the gesture must not follow that.
        let source: Int
        let photo: ContentHash
        var translation: CGSize = .zero
        var target: Int?
    }

    private static let space = "sheet"

    private var settings: SheetSettings { controller.settings }

    /// While dragging, the sheet shows where everything would go if the
    /// photograph were dropped now. The others make room as it passes over them,
    /// which is how the shift is seen before it is committed.
    private var shown: Arrangement {
        guard let drag, let target = drag.target else { return controller.arrangement }
        return controller.arrangement.moving(from: drag.source, to: target)
    }

    var body: some View {
        GeometryReader { proxy in
            let cells = layout(
                cols: settings.columns,
                rows: settings.rows,
                gap: settings.gap,
                cellAspect: controller.cellAspect,
                canvas: proxy.size
            )

            let shown = self.shown

            ZStack(alignment: .topLeading) {
                // The canvas is the window, so the whole area is the sheet —
                // including the dead space at the two edges that do not bind.
                Color(settings.background)
                    .onTapGesture { hasKeyboardFocus = true }

                // Iterating the photographs that are placed, keyed by
                // photograph, is what lets a frame *move* to its new cell when
                // the sheet is rolled rather than cross-fading in place. The
                // movement is how the eye registers what changed.
                ForEach(placed(shown, in: cells.count), id: \.reference.id) { item in
                    let dragged = drag.flatMap { $0.photo == item.reference.id ? $0 : nil }
                    // The dragged photograph stays under the pointer; everything
                    // else sits in the cell the preview gives it.
                    let home = dragged.map { cells[$0.source] } ?? cells[item.cell]
                    let offset = dragged?.translation ?? .zero

                    SheetCell(
                        reference: item.reference,
                        size: cells[item.cell].size,
                        background: settings.background,
                        isPinned: shown.isPinned(cell: item.cell)
                    )
                    .frame(width: cells[item.cell].width, height: cells[item.cell].height)
                    .shadow(color: .black.opacity(dragged == nil ? 0 : 0.3), radius: 10, y: 4)
                    .position(x: home.midX + offset.width, y: home.midY + offset.height)
                    // Following the pointer must never lag behind it, even when
                    // the cells around it are animating into the preview.
                    .transaction { if dragged != nil { $0.animation = nil } }
                    .zIndex(dragged == nil ? 0 : 1)
                    // One handler, reading the modifiers itself.
                    //
                    // Attaching a separate `.modifiers(.command)` gesture does
                    // not work here: a plain `onTapGesture` fires for a modified
                    // click as well, so both would run and the order between
                    // them is not ours to decide. Branching on the flags keeps
                    // the whole convention in one readable place.
                    .onTapGesture {
                        hasKeyboardFocus = true
                        controller.click(
                            cell: item.cell,
                            modifiers: NSEvent.modifierFlags,
                            clickCount: NSApp.currentEvent?.clickCount ?? 1
                        )
                    }
                    .gesture(dragGesture(cell: item.cell, photo: item.reference.id, cells: cells))
                }

                // Shown whenever something is selected, not only while this
                // view holds the keyboard: selection is what Delete acts on, so
                // it has to outlast the click that made it.
                // Hidden mid-drag: the ring is by cell, and the preview is moving
                // photographs out from under it.
                ForEach(drag == nil ? controller.selectedCells.sorted().filter(cells.indices.contains) : [], id: \.self) { selected in
                    let cell = cells[selected]
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color(settings.background.contrastingInk).opacity(0.55), lineWidth: 2)
                        .frame(width: cell.width + 6, height: cell.height + 6)
                        .position(x: cell.midX, y: cell.midY)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(.named(Self.space))
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
            if controller.showingShortcuts {
                controller.showingShortcuts = false
            } else if controller.showingLightbox {
                controller.closeLightbox()
            } else {
                return .ignored
            }
            return .handled
        }
        .overlay {
            ZStack {
                if let cell = controller.lightboxCell,
                   let id = controller.arrangement.photograph(at: cell),
                   let reference = controller.reference(for: id) {
                    LightboxView(
                        reference: reference,
                        isPinned: controller.arrangement.isPinned(cell: cell),
                        background: settings.background
                    ) {
                        hasKeyboardFocus = true
                        controller.closeLightbox()
                    }
                }
                if controller.showingShortcuts {
                    ShortcutLegend { controller.showingShortcuts = false }
                }
            }
        }
    }

    private struct Placement {
        let cell: Int
        let reference: PhotoReference
    }

    /// Drag a photograph onto any cell. It moves there and is pinned; the cells
    /// between shift one place. Dropped in the dead space beyond the block, or
    /// back where it started, it returns and nothing is recorded.
    private func dragGesture(cell: Int, photo: ContentHash, cells: [CGRect]) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil { drag = Drag(source: cell, photo: photo) }
                drag?.translation = value.translation
                let target = PhotomancyCore.cell(at: value.location, in: cells, gap: settings.gap)
                if target != drag?.target {
                    controller.stepping { drag?.target = target }
                }
            }
            .onEnded { _ in
                guard let ended = drag else { return }
                hasKeyboardFocus = true
                controller.stepping {
                    drag = nil
                    if let target = ended.target {
                        controller.move(from: ended.source, to: target)
                    }
                }
            }
    }

    private func placed(_ arrangement: Arrangement, in cellCount: Int) -> [Placement] {
        arrangement.slots.prefix(cellCount).enumerated().compactMap { cell, id in
            guard let id, let reference = controller.reference(for: id) else { return nil }
            return Placement(cell: cell, reference: reference)
        }
    }
}
