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

/// The sheet: a true rows × columns grid, positioned from `sheetGeometry()`.
///
/// Deliberately not a `LazyVGrid`. Its geometry would be invisible to the print
/// path and the two would drift apart, which surfaces as "it didn't print the
/// way it looked". Every rectangle here is one the print path is handed
/// unchanged, under one uniform transform onto the page.
struct SheetView: View {

    @Environment(LibraryController.self) private var controller

    @FocusState private var hasKeyboardFocus: Bool

    /// Pixels per point, which is what the cache budget is reckoned in.
    @Environment(\.displayScale) private var displayScale

    /// A drag in progress. Nothing is committed until the photograph is dropped,
    /// so a drag abandoned in the margin leaves no step in the history.
    @State private var drag: Drag?

    private struct Drag: Equatable {
        /// Captured once, when the drag begins — the preview renumbers cells
        /// under the pointer, and the gesture must not follow that.
        let source: Int
        let photo: ContentHash
        /// What leaves if the drag is dropped on the sidebar: the selection when
        /// the drag started on it, otherwise just this photograph. In sheet
        /// order, so the stack under the pointer is too.
        let carried: [ContentHash]
        var translation: CGSize = .zero
        /// The pointer, in the sheet's coordinates.
        var location: CGPoint = .zero
        var target: Int?
        /// Out of the sheet and over the sidebar.
        var isOut = false
    }

    private static let space = "sheet"

    /// The long edge of each photograph in the stack under the pointer.
    private static let stackEdge: CGFloat = 110

    private var settings: SheetSettings { controller.settings }

    /// While dragging, the sheet shows where everything would go if the
    /// photograph were dropped now. The others make room as it passes over them,
    /// which is how the shift is seen before it is committed.
    private var shown: Arrangement {
        guard let drag, let target = drag.target else { return controller.arrangement }
        return controller.arrangement.moving(drag.carried, to: target)
    }

    var body: some View {
        GeometryReader { proxy in
            // One geometry for the screen and the page. It clamps the gap for
            // a window too small for the stored one — which is why the print
            // path calls this and never `layout()` directly: laying out at the
            // stored gap there would print a sheet that is not the one on
            // screen, in exactly that case.
            let geometry = sheetGeometry(
                settings: settings,
                cellAspect: controller.cellAspect,
                canvas: proxy.size
            )
            let gap = geometry.gap
            let cells = geometry.cells

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
                    let cell = cells[item.cell]
                    let dragged = drag.flatMap { $0.photo == item.reference.id ? $0 : nil }
                    let rank = drag?.carried.firstIndex(of: item.reference.id)
                    // A drag of more than one gathers from the moment it
                    // starts, not at the sheet's edge: found in use on
                    // 2026-09-20 — with the others left in their cells, a drag
                    // of several read as dragging one until the pointer was
                    // already over the sidebar.
                    let gathered = rank != nil && (drag?.carried.count ?? 0) > 1
                    let place = placement(of: item, cell: cell, dragged: dragged, rank: rank, gathered: gathered, cells: cells)

                    SheetCell(
                        reference: item.reference,
                        size: cell.size,
                        background: settings.background,
                        isPinned: shown.isPinned(cell: item.cell)
                    )
                    .frame(width: cell.width, height: cell.height)
                    // During a drag the rings travel with the photographs they
                    // belong to rather than staying on cells, so a selection
                    // being carried still reads as selected.
                    .overlay {
                        if drag != nil, rank != nil, drag?.carried.count ?? 0 > 1 {
                            selectionRing
                                .padding(-3)
                        }
                    }
                    .scaleEffect(place.scale)
                    .shadow(color: .black.opacity(dragged != nil || gathered ? 0.3 : 0), radius: 10, y: 4)
                    .position(place.center)
                    // Following the pointer must never lag behind it, even when
                    // the cells around it are animating into the preview.
                    .transaction { if dragged != nil { $0.animation = nil } }
                    .zIndex(dragged != nil ? 3 : gathered ? 2 : 0)
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
                    .gesture(dragGesture(cell: item.cell, photo: item.reference.id, cells: cells, gap: gap, canvas: proxy.size))
                    .contextMenu { MoveMenu(controller: controller, cell: item.cell) }
                }

                // How many are going, as Finder counts a drag — on the top of the
                // stack, only when there is more than one.
                if let drag, drag.carried.count > 1 {
                    let edge = Self.stackEdge / 2
                    Text("\(drag.carried.count)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .position(x: drag.location.x + edge, y: drag.location.y - edge * 0.7)
                        .allowsHitTesting(false)
                        .zIndex(4)
                }

                // Shown whenever something is selected, not only while this
                // view holds the keyboard: selection is what Delete acts on, so
                // it has to outlast the click that made it.
                // During a drag the rings are drawn on the photographs instead —
                // the preview moves photographs out from under these cells.
                ForEach(drag == nil ? controller.selectedCells.sorted().filter(cells.indices.contains) : [], id: \.self) { selected in
                    let cell = cells[selected]
                    selectionRing
                        .frame(width: cell.width + 6, height: cell.height + 6)
                        .position(x: cell.midX, y: cell.midY)
                }
            }
            .coordinateSpace(.named(Self.space))
            .onChange(of: proxy.size, initial: true) { _, size in controller.canvas = size }
            .onChange(of: displayScale, initial: true) { _, scale in controller.displayScale = scale }
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

    /// The system accent, as every Mac list and icon grid marks a selection.
    /// Derived from the sheet background it was elegant and, on the grey preset,
    /// invisible — and a ring nobody can see is not a selection. It also has to
    /// read while a drag carries it, which is when it matters most.
    private var selectionRing: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .allowsHitTesting(false)
    }

    private struct Placement {
        let cell: Int
        let reference: PhotoReference
    }

    /// Where a photograph is drawn, and at what size.
    ///
    /// In its cell, normally. The dragged one follows the pointer. When more
    /// than one is carried, everything gathers under the pointer for the whole
    /// drag, shrunk to a small stack in sheet order with the dragged one on top
    /// — so a selection is seen leaving together, not only the photograph under
    /// the pointer. Dropped back on a cell only the dragged one moves, as ever;
    /// the stack says what is being carried, not what a cell would take.
    private func placement(
        of item: Placement,
        cell: CGRect,
        dragged: Drag?,
        rank: Int?,
        gathered: Bool,
        cells: [CGRect]
    ) -> (center: CGPoint, scale: CGFloat) {
        guard let drag else { return (CGPoint(x: cell.midX, y: cell.midY), 1) }
        if gathered, let rank {
            let scale = min(1, Self.stackEdge / max(cell.width, cell.height, 1))
            // Up to three behind the top one are fanned; the rest sit under them.
            let depth = CGFloat(min(dragged != nil ? 0 : rank + 1, 3))
            return (CGPoint(x: drag.location.x - depth * 5, y: drag.location.y - depth * 5), scale)
        }
        if dragged != nil {
            let home = cells[drag.source]
            return (CGPoint(x: home.midX + drag.translation.width, y: home.midY + drag.translation.height), 1)
        }
        return (CGPoint(x: cell.midX, y: cell.midY), 1)
    }

    /// Drag a photograph onto any cell. It moves there and is pinned; the cells
    /// between shift one place. Dropped in the dead space beyond the block, or
    /// back where it started, it returns and nothing is recorded.
    ///
    /// Carried out of the sheet and onto the sidebar, it is a different act: the
    /// photograph — and the rest of the selection, if it was selected — moves to
    /// the collection it is dropped on, or to a new one on empty sidebar space.
    /// Within the sheet only ever the one photograph moves.
    private func dragGesture(cell: Int, photo: ContentHash, cells: [CGRect], gap: Double, canvas: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if drag == nil {
                    let carried = controller.cellsCarried(from: cell).sorted()
                        .compactMap { controller.arrangement.photograph(at: $0) }
                    drag = Drag(source: cell, photo: photo, carried: carried)
                }
                drag?.translation = value.translation
                drag?.location = value.location

                let outbound = sidebarDrop(at: value.location, canvas: canvas)
                if outbound != controller.sidebarDrop {
                    controller.stepping { controller.sidebarDrop = outbound }
                }
                let isOut = outbound != nil
                if isOut != drag?.isOut {
                    // Gathering into the stack, or back into the cells, is seen
                    // moving — that is what says which of the two drags this is.
                    controller.stepping { drag?.isOut = isOut }
                }
                // Over the sidebar the sheet previews nothing of its own.
                let target = isOut ? nil : PhotomancyCore.cell(at: value.location, in: cells, gap: gap)
                if target != drag?.target {
                    controller.stepping { drag?.target = target }
                }
            }
            .onEnded { _ in
                guard let ended = drag else { return }
                hasKeyboardFocus = true
                let outbound = controller.sidebarDrop
                controller.stepping {
                    drag = nil
                    controller.sidebarDrop = nil
                    if let outbound {
                        controller.drop(from: ended.source, on: outbound)
                    } else if let target = ended.target {
                        controller.move(from: ended.source, to: target)
                    }
                }
            }
    }

    /// Only asked once the pointer has left the sheet. The drag's own event
    /// carries the pointer in window coordinates, which is what the sidebar's
    /// targets are measured in.
    private func sidebarDrop(at location: CGPoint, canvas: CGSize) -> SidebarDrop? {
        guard !CGRect(origin: .zero, size: canvas).contains(location),
              let event = NSApp.currentEvent,
              let window = event.window ?? NSApp.keyWindow
        else { return nil }
        return controller.dropZones.drop(atWindowPoint: event.locationInWindow, in: window, source: controller.selection)
    }

    private func placed(_ arrangement: Arrangement, in cellCount: Int) -> [Placement] {
        arrangement.slots.prefix(cellCount).enumerated().compactMap { cell, id in
            guard let id, let reference = controller.reference(for: id) else { return nil }
            return Placement(cell: cell, reference: reference)
        }
    }
}
