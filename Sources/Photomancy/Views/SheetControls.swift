import SwiftUI
import AppKit
import PhotomancyCore

/// Columns, rows, gap and background, written straight to the collection's
/// settings. Small, quiet, always in the same place.
///
/// Numbers are typed, not dragged: "padding, exact to the pixel" means a field.
/// Each has a stepper beside it for the pointer route. The only limits are
/// physical — what the window can show — and live in the controller.
struct SheetControls: View {

    @Environment(LibraryController.self) private var controller
    @FocusState private var focused: Field?

    private enum Field { case columns, rows, gap }

    var body: some View {
        @Bindable var controller = controller

        HStack(spacing: 18) {
            number("Columns", value: $controller.columns, field: .columns)
            number("Rows", value: $controller.rows, field: .rows)
            number("Gap", value: gap, field: .gap, unit: "px")

            HStack(spacing: 6) {
                label("Background")
                // Opaque only: paper has no transparency.
                ColorPicker("Background", selection: background, supportsOpacity: false)
                    .labelsHidden()
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
        // Space, P, ⌫ and Return are bare-key menu items; while a field has the
        // keyboard they must yield, or nobody can type into it.
        .onChange(of: focused) { _, field in controller.isEditingText = field != nil }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func number(_ name: String, value: Binding<Int>, field: Field, unit: String? = nil) -> some View {
        HStack(spacing: 6) {
            label(name)
            HStack(spacing: 2) {
                TextField(name, value: value, format: .number.grouping(.never))
                    .labelsHidden()
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .focused($focused, equals: field)
                    .onSubmit { focused = nil }
                Stepper(name, onIncrement: { value.wrappedValue += 1 }, onDecrement: { value.wrappedValue -= 1 })
                    .labelsHidden()
            }
            if let unit { label(unit) }
        }
    }

    private var gap: Binding<Int> {
        Binding(get: { Int(controller.gap) }, set: { controller.gap = Double($0) })
    }

    private var background: Binding<Color> {
        Binding(
            get: { Color(controller.background) },
            set: { picked in
                if let converted = SheetColor(convertingToSRGB: NSColor(picked).cgColor) {
                    controller.background = converted
                }
            }
        )
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
