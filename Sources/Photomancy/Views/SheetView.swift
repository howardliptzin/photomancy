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

    let photographs: [PhotoReference]
    let settings: SheetSettings
    let cellAspect: Double

    var body: some View {
        GeometryReader { proxy in
            let canvas = proxy.size
            let cells = layout(
                cols: settings.columns,
                rows: settings.rows,
                gap: settings.gap,
                cellAspect: cellAspect,
                canvas: canvas
            )

            ZStack(alignment: .topLeading) {
                // The canvas is the window, so the whole area is the sheet —
                // including the dead space at the two edges that do not bind.
                Color(settings.background)

                // Iterating photographs rather than cells is what makes a cell
                // with nothing in it draw nothing at all: no outline, no
                // placeholder, identical on screen and on paper. Keyed by
                // photograph so M3 can animate a frame from one cell to another.
                ForEach(Array(photographs.prefix(cells.count).enumerated()), id: \.element.id) { index, reference in
                    SheetCell(
                        reference: reference,
                        size: cells[index].size,
                        background: settings.background
                    )
                    .frame(width: cells[index].width, height: cells[index].height)
                    .position(x: cells[index].midX, y: cells[index].midY)
                }
            }
        }
    }
}
