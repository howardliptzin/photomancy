import AppKit
import os
import PhotomancyCore

/// Usable from the print operation's own thread, unlike anything on a
/// main-actor type.
let printLog = Logger(subsystem: AppPaths.bundleIdentifier, category: "print")

/// Everything one print job needs, gathered on the main thread and then never
/// touched again.
///
/// The point of the struct is that it is finished: the operation renders on a
/// thread AppKit makes for it, and anything it reads has to be immutable by
/// then. Nothing here reaches back into the controller, the store or the cache.
struct SheetPrintJob: @unchecked Sendable {
    let geometry: SheetGeometry
    let background: SheetColor
    let placements: [PrintImages.Placement]
    /// Thumbnails, for the panel's preview only — it is a screen, and it has to
    /// be instant. Nothing here ever reaches paper.
    let previewFrames: [SheetRenderer.Frame]
    let resolver: BookmarkResolver
    let title: String
}

/// The view `NSPrintOperation` draws.
///
/// **Every override is `nonisolated`, and it holds nothing but the job.** Step 0
/// measured this with a crash: `canSpawnSeparateThread` renders on a secondary
/// thread, and under Swift 6 an `NSView` subclass's overrides are implicitly
/// `@MainActor`, so the first one AppKit called trapped. A printed view that
/// looks perfectly ordinary is the bug.
///
/// `isFlipped` is deliberately **not** overridden. The default is `false`, which
/// is what this needs: `pageTransform` already maps the screen's top-left origin
/// into Quartz's bottom-left, so a flipped view would apply that turn twice and
/// print the sheet upside down.
///
/// ## The isolation warnings in here are the price of the above
///
/// AppKit annotates `NSPrintOperation` and `NSView`'s geometry `@MainActor`,
/// and then documents printing as happening on a thread of its own — the two
/// cannot both be honoured, and the compiler says so five times in this file.
/// They are warnings rather than errors because AppKit is imported
/// preconcurrency, and no runtime check is inserted for them. The alternative,
/// wrapping the reads in `MainActor.assumeIsolated`, does insert one, and would
/// reintroduce exactly the crash step 0 found. Step 0 measured this pattern
/// working on the spawned thread. Everything avoidable has been moved off the
/// printing thread; what is left is the irreducible part.
final class PrintedSheetView: NSView {

    private let job: SheetPrintJob
    private let state: State

    /// What the printing thread writes and reads, kept off AppKit's geometry so
    /// the draw pass needs no main-actor property at all.
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var size: CGSize
        private var failure: (any Error)?

        init(size: CGSize) { self.size = size }

        /// The imageable area of the paper the panel actually ended on.
        var pageSize: CGSize {
            get { lock.withLock { size } }
            set { lock.withLock { size = newValue } }
        }

        var error: (any Error)? {
            get { lock.withLock { failure } }
            set { lock.withLock { failure = newValue } }
        }
    }

    var error: (any Error)? { state.error }

    init(job: SheetPrintJob, imageable: CGSize) {
        self.job = job
        self.state = State(size: imageable)
        super.init(frame: NSRect(origin: .zero, size: imageable))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    /// One page, always — no pagination, and no page breaks.
    ///
    /// Also where the view learns what paper the panel actually ended on. This
    /// runs at operation time, on the printing thread, *after* the panel is
    /// dismissed, so paper changed inside the panel is honoured — by the decode
    /// as well as by the drawing, which is the whole reason the originals are
    /// not decoded before the panel opens. The same call happens for each
    /// preview render, which is what makes the preview follow the paper while
    /// it is still being chosen.
    nonisolated override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        if let imageable = NSPrintOperation.current?.printInfo.imageablePageBounds,
           imageable.width > 0, imageable.height > 0, imageable.size != state.pageSize {
            state.pageSize = imageable.size
            setFrameSize(imageable.size)
        }
        range.pointee = NSRange(location: 1, length: 1)
        return true
    }

    nonisolated override func rectForPage(_ page: Int) -> NSRect {
        CGRect(origin: .zero, size: state.pageSize)
    }

    nonisolated override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Step 0 found the discriminator, and found that the obvious one does
        // not work: `isDrawingToScreen` is false for both passes. The panel's
        // preview draws report `responsive` on the main thread; the output draw
        // reports `best` on the thread AppKit spawned for it.
        let isOutput = NSPrintOperation.current?.preferredRenderingQuality == .best
        let printable = CGRect(origin: .zero, size: state.pageSize)

        let frames: [SheetRenderer.Frame]
        if isOutput {
            do {
                frames = try PrintImages.frames(
                    for: job.placements,
                    geometry: job.geometry,
                    printable: printable,
                    resolver: job.resolver
                )
            } catch {
                // Reported on the main thread once the operation ends. The
                // thumbnails are printed rather than nothing, because a soft
                // sheet beats a blank page and the person is told either way.
                state.error = error
                printLog.error("print: decoding originals failed — \(error.localizedDescription, privacy: .public)")
                frames = job.previewFrames
            }
        } else {
            frames = job.previewFrames
        }

        SheetRenderer(geometry: job.geometry, background: job.background, frames: frames)
            .draw(in: context, onto: printable)
    }
}

/// States what the sheet will measure on the paper currently chosen, and follows
/// it as the choice changes.
///
/// The sentence itself comes from `PrintMetrics.summary` in Core, where it is
/// tested. This only puts it on screen.
final class PrintMetricsAccessory: NSViewController, NSPrintPanelAccessorizing {

    private let geometry: SheetGeometry
    private let label = NSTextField(labelWithString: "")

    init(geometry: SheetGeometry) {
        self.geometry = geometry
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 12),
        ])
        view = container
        refresh()
    }

    /// The panel sets this to the `NSPrintInfo` it is editing.
    override var representedObject: Any? {
        didSet { refresh() }
    }

    private var printInfo: NSPrintInfo? { representedObject as? NSPrintInfo }

    private var metrics: PrintMetrics? {
        guard let printInfo else { return nil }
        return printMetrics(for: geometry, onto: printInfo.imageablePageBounds)
    }

    private func refresh() {
        label.stringValue = metrics?.summary ?? "Nothing to print."
    }

    /// Changing any of these re-renders the preview — and the panel asks for the
    /// summary again, which is what keeps the sentence honest as paper and
    /// orientation change.
    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["representedObject.paperSize", "representedObject.orientation",
         "representedObject.leftMargin", "representedObject.rightMargin",
         "representedObject.topMargin", "representedObject.bottomMargin"]
    }

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        refresh()
        guard let metrics else { return [] }
        return [[
            .itemName: "Photomancy",
            .itemDescription: metrics.summary,
        ]]
    }
}

/// Only exists to hear how the operation ended — the panel is another process,
/// so this is the app's own account of it.
final class SheetPrintDelegate: NSObject {

    @MainActor static let shared = SheetPrintDelegate()

    /// Called back on the main thread when the job is over, whatever the
    /// outcome. Set fresh for each job.
    @MainActor var didFinish: ((NSPrintOperation, Bool) -> Void)?

    @MainActor
    @objc func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        printLog.info("print: operation ended success=\(success, privacy: .public)")
        didFinish?(operation, success)
        didFinish = nil
    }
}

// MARK: - Paper, both ways

extension Paper {

    /// The paper the panel ended on, whatever it was.
    init(printInfo: NSPrintInfo) {
        self.init(points: printInfo.paperSize, name: printInfo.paperName?.rawValue)
    }

    /// Open the panel on the paper this collection was last printed on.
    ///
    /// The printer's own name for it is applied first when there is one, so the
    /// panel reopens on *that* paper rather than on whatever else happens to be
    /// the same size; the size is then set regardless, which is what carries
    /// paper the current printer does not offer.
    func apply(to printInfo: NSPrintInfo) {
        if let paperName {
            printInfo.paperName = NSPrinter.PaperName(rawValue: paperName)
        }
        printInfo.paperSize = points
        printInfo.orientation = orientation == .landscape ? .landscape : .portrait
    }
}
