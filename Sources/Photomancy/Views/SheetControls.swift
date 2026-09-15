import SwiftUI
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
                // The common three, one click each, then the colour wheel for
                // anything else. One ring for the row: on a preset's swatch, or on
                // the wheel when the colour is custom.
                HStack(spacing: 4) {
                    ForEach(SheetColor.presets, id: \.self) { preset in
                        swatch(preset)
                    }
                }
                Divider().frame(height: 14)
                colorWheel
            }

            // Space is the gesture; this is the same action for the pointer, in
            // the bar with everything else that shapes the sheet.
            Button("Randomize") { controller.randomize() }
                .controlSize(.small)
                .help("Randomize the sheet (Space)")

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

    private func swatch(_ preset: SheetColor.Preset) -> some View {
        let selected = controller.background.matchingPreset == preset
        return Button {
            controller.background = preset.color
        } label: {
            ringed(selected) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(preset.color))
                    // A hairline, so white still reads against a pale bar.
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                    .frame(width: 15, height: 15)
            }
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .accessibilityLabel("\(preset.name) background")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The colour wheel — the Mac's own sign for "any colour". Opens the Colors
    /// window. Ringed when the background is none of the presets, and then shows
    /// that colour in its centre, so a custom colour is visible at a glance.
    private var colorWheel: some View {
        let controller = self.controller
        let background = controller.background
        let custom = background.matchingPreset == nil
        return Button {
            ColorPanel.shared.open(with: background) { controller.background = $0 }
        } label: {
            ringed(custom) {
                ZStack {
                    Circle().strokeBorder(
                        AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center),
                        lineWidth: 3.5
                    )
                    if custom {
                        Circle().fill(Color(background)).padding(4)
                    }
                }
                .frame(width: 15, height: 15)
            }
        }
        .buttonStyle(.plain)
        .help("Any colour…")
        .accessibilityLabel("Custom background colour")
        .accessibilityAddTraits(custom ? .isSelected : [])
    }

    /// The one selection mark for the whole background row.
    private func ringed<Content: View>(_ selected: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(2)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
    }

    private var gap: Binding<Int> {
        Binding(get: { Int(controller.gap) }, set: { controller.gap = Double($0) })
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
