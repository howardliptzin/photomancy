// M5 STEP 0 SPIKE — throwaway. Measures what the print panel does in the sandbox.
import AppKit
import OSLog
import PhotomancyCore

/// Usable from the print operation's own thread, unlike anything on the
/// main-actor type below.
let spikeLog = Logger(subsystem: AppPaths.bundleIdentifier, category: "spike")

@MainActor
enum SpikePrint {
    static let log = spikeLog

    /// Does a save panel open at all on the read-only entitlement?
    ///
    /// The print panel's Save as PDF is an `NSSavePanel` in this process, so
    /// this is the same gate without needing the panel's own buttons — which
    /// belong to another process and cannot be driven from here. If the
    /// entitlement is what blocks it, `runModal` returns without showing
    /// anything and AppKit says why in the log.
    static func savePanel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "spike.pdf"
        panel.allowedContentTypes = [.pdf]
        log.notice("spike: about to run a save panel")
        let response = panel.runModal()
        log.notice("spike: save panel returned \(response.rawValue, privacy: .public), url=\(panel.url?.path ?? "none", privacy: .public)")
        guard let url = panel.url else { return }
        // If a panel did open, does the grant it hands back permit a write?
        let data = Data("%PDF-1.4 spike\n".utf8)
        do {
            try data.write(to: url)
            log.notice("spike: wrote \(data.count, privacy: .public) bytes to \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("spike: write failed — \(error.localizedDescription, privacy: .public) (\(String(describing: error), privacy: .public))")
        }
    }

    /// Renders to a PDF without any panel — the output pass on its own thread,
    /// which is what crashed, with nothing to click.
    static func renderToContainer() {
        guard let directory = try? AppPaths.applicationSupport() else { return }
        let url = directory.appendingPathComponent("spike-auto.pdf")
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.orientation = .landscape
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let view = SpikeSheetView(frame: NSRect(origin: .zero, size: info.imageablePageBounds.size))
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.canSpawnSeparateThread = true
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        log.notice("spike: rendering to \(url.path, privacy: .public)")
        let ok = operation.run()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        log.notice("spike: render returned \(ok, privacy: .public), file \(size ?? -1, privacy: .public) bytes")
    }

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
            operation.runModal(
                for: window,
                delegate: SpikePrintDelegate.shared,
                didRun: #selector(SpikePrintDelegate.printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        } else {
            let ok = operation.run()
            log.notice("spike: run returned \(ok, privacy: .public)")
        }
    }
}

/// Holds nothing mutable and touches no app state, so every override AppKit may
/// call while printing is `nonisolated`. Without this, Swift 6 traps the moment
/// the print operation renders on its own thread — which is exactly what
/// `canSpawnSeparateThread` asks it to do.
final class SpikeSheetView: NSView {
    nonisolated override var isFlipped: Bool { true }

    nonisolated override func draw(_ dirtyRect: NSRect) {
        let toScreen = NSGraphicsContext.current?.isDrawingToScreen ?? false
        let current = NSPrintOperation.current
        let paper = current?.printInfo.paperSize ?? .zero
        let path = current?.printInfo.jobDisposition.rawValue ?? "-"
        let quality = current.map { $0.preferredRenderingQuality == .best ? "best" : "responsive" } ?? "none"
        let saveURL = (current?.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL)?.lastPathComponent ?? "-"
        spikeLog.notice(
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


/// Only exists to hear how the print operation ended — the panel itself is
/// another process, so this is the app's own account of it.
final class SpikePrintDelegate: NSObject {
    @MainActor static let shared = SpikePrintDelegate()

    @MainActor
    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        let disposition = operation.printInfo.jobDisposition.rawValue
        let saving = (operation.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] as? URL)?.path ?? "none"
        SpikePrint.log.notice("spike: operation ended success=\(success, privacy: .public) disposition=\(disposition, privacy: .public) savingURL=\(saving, privacy: .public)")
    }
}
