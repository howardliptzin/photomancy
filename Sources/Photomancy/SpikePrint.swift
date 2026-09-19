// M5 STEP 0 SPIKE — throwaway. Measures what the print panel does in the sandbox.
import AppKit
import OSLog
import PhotomancyCore

@MainActor
enum SpikePrint {
    static let log = Logger(subsystem: AppPaths.bundleIdentifier, category: "spike")

    static func run() {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        let view = SpikeSheetView(frame: NSRect(origin: .zero, size: info.imageablePageBounds.size))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.canSpawnSeparateThread = true
        operation.jobTitle = "Photomancy spike"
        log.notice("spike: running print operation, paper \(info.paperSize.width, privacy: .public)x\(info.paperSize.height, privacy: .public)")
        if let window = NSApp.keyWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            let ok = operation.run()
            log.notice("spike: run returned \(ok, privacy: .public)")
        }
    }
}

final class SpikeSheetView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let toScreen = NSGraphicsContext.current?.isDrawingToScreen ?? false
        let current = NSPrintOperation.current
        let paper = current?.printInfo.paperSize ?? .zero
        let path = current?.printInfo.jobDisposition.rawValue ?? "-"
        let quality = current.map { $0.preferredRenderingQuality == .best ? "best" : "responsive" } ?? "none"
        let saveURL = (current?.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL)?.lastPathComponent ?? "-"
        Logger(subsystem: AppPaths.bundleIdentifier, category: "spike").notice(
            "spike draw: toScreen=\(toScreen, privacy: .public) main=\(Thread.isMainThread, privacy: .public) paper=\(paper.width, privacy: .public)x\(paper.height, privacy: .public) disposition=\(path, privacy: .public) quality=\(quality, privacy: .public) saveURL=\(saveURL, privacy: .public) bounds=\(self.bounds.width, privacy: .public)x\(self.bounds.height, privacy: .public)")
        NSColor(srgbRed: 0x93 / 255, green: 0x92 / 255, blue: 0x92 / 255, alpha: 1).setFill()
        bounds.fill()
        NSColor.black.setFill()
        let cols = 5, rows = 4, gap: CGFloat = 12
        let w = (bounds.width - gap * CGFloat(cols + 1)) / CGFloat(cols)
        let h = (bounds.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        for r in 0..<rows { for c in 0..<cols {
            NSRect(x: gap + CGFloat(c) * (w + gap), y: gap + CGFloat(r) * (h + gap), width: w, height: h).fill()
        } }
    }
}
