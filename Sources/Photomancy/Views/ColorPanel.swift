import AppKit
import PhotomancyCore

/// The system Colors window, driven for the sheet's background.
///
/// SwiftUI's `ColorPicker` draws a colour well that, on a white background, is an
/// empty white capsule — it does not read as a colour control. The colour wheel
/// beside the presets opens the same window directly, and this receives what is
/// picked. Converted into sRGB rather than reinterpreted: the window hands back
/// colours in whatever space was picked, Display P3 among them.
@MainActor
final class ColorPanel: NSObject {

    static let shared = ColorPanel()

    private var onChange: ((SheetColor) -> Void)?

    func open(with color: SheetColor, onChange: @escaping (SheetColor) -> Void) {
        let panel = NSColorPanel.shared
        // Detached while the starting colour is set, so opening the window is
        // not itself recorded as a choice.
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false   // paper has no transparency
        panel.isContinuous = true
        panel.color = NSColor(cgColor: color.cgColor) ?? .white
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ sender: NSColorPanel) {
        guard let picked = SheetColor(convertingToSRGB: sender.color.cgColor) else { return }
        onChange?(picked)
    }
}
