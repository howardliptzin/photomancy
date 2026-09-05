import SwiftUI
import PhotomancyCore

/// Columns, rows and gap, written straight to the collection's settings.
///
/// The minimum needed to watch the sheet reflow. The considered version arrives
/// in M4 with the rest of the per-collection settings; this exists so M2 can be
/// judged at all.
struct SheetControls: View {

    @Environment(LibraryController.self) private var controller

    var body: some View {
        @Bindable var controller = controller

        HStack(spacing: 18) {
            Stepper(value: $controller.columns, in: 1...64) {
                measure("Columns", controller.columns)
            }
            Stepper(value: $controller.rows, in: 1...64) {
                measure("Rows", controller.rows)
            }

            HStack(spacing: 8) {
                Text("Gap").font(.caption).foregroundStyle(.secondary)
                Slider(value: $controller.gap, in: 0...48, step: 1)
                    .frame(width: 130)
                Text("\(Int(controller.gap)) px")
                    .font(.caption).monospacedDigit()
                    .frame(width: 42, alignment: .leading)
            }

            Spacer(minLength: 12)

            Text(tally)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func measure(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.caption).monospacedDigit()
        }
    }

    /// Says plainly when a roll will be sampling from a bigger pool, and when
    /// cells will be left empty. Both are ordinary states, not warnings.
    private var tally: String {
        let photographs = controller.photographs.count
        let cells = controller.cellCount
        if photographs > cells {
            return "\(photographs) photographs · \(cells) cells · each roll samples"
        } else if photographs < cells {
            return "\(photographs) photographs · \(cells) cells · \(cells - photographs) empty"
        }
        return "\(photographs) photographs · \(cells) cells"
    }
}
