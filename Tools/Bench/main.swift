import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import PhotomancyCore

// Measures the thumbnail pipeline on real photographs, from the shell, using
// the same Core the app links. Unsandboxed on purpose: the point is to measure
// decoding, not to re-test the sandbox.
//
//   photomancy-bench <file-or-folder>... [--size 512] [--count 30]

struct Options {
    var paths: [String] = []
    var sizes: [Int] = []
    var count = 30
}

func parseOptions() -> Options {
    var options = Options()
    var arguments = Array(CommandLine.arguments.dropFirst())
    while let argument = arguments.first {
        arguments.removeFirst()
        switch argument {
        case "--size":
            if let value = arguments.first.flatMap(Int.init) { options.sizes.append(value); arguments.removeFirst() }
        case "--count":
            if let value = arguments.first.flatMap(Int.init) { options.count = value; arguments.removeFirst() }
        default:
            options.paths.append(argument)
        }
    }
    if options.sizes.isEmpty { options.sizes = [512, 1024] }
    return options
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let position = fraction * Double(sorted.count - 1)
    let lower = Int(position.rounded(.down))
    let upper = Int(position.rounded(.up))
    guard lower != upper else { return sorted[lower] }
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
}

func milliseconds(_ body: () throws -> Void) rethrows -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    try body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

func formatFamily(_ url: URL) -> String? {
    guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return nil }
    if type.conforms(to: .jpeg) { return "JPEG" }
    if type.conforms(to: .heic) || type.conforms(to: .heif) { return "HEIC" }
    if type.conforms(to: .png) { return "PNG" }
    if type.conforms(to: .tiff) { return "TIFF" }
    if type.conforms(to: .rawImage) { return "RAW" }
    return type.conforms(to: .image) ? "other" : nil
}

func fileSize(_ url: URL) -> Int {
    (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
}

// ── a picture of what layout() actually returns ──────────────────────────────
//
// The geometry is covered by tests, but its *placement* is not, and a
// half-a-cell offset produces a plausible grid that is subtly wrong. Drawing the
// real rectangles into a CGContext is both the check for that and a rehearsal
// for M5, where the print path does exactly this.
//
//   photomancy-bench --render-layout out.png <cols> <rows> <gap> <aspect|fill> <w> <h>
if let flag = CommandLine.arguments.firstIndex(of: "--render-layout") {
    let a = Array(CommandLine.arguments.dropFirst(flag + 1))
    guard a.count >= 7,
          let cols = Int(a[1]), let rows = Int(a[2]), let gap = Double(a[3]),
          let width = Double(a[5]), let height = Double(a[6])
    else {
        print("usage: --render-layout out.png <cols> <rows> <gap> <aspect|fill> <w> <h>")
        exit(2)
    }
    let aspect: Double? = a[4] == "fill" ? nil : Double(a[4])
    let canvas = CGSize(width: width, height: height)
    let cells = layout(cols: cols, rows: rows, gap: gap, cellAspect: aspect, canvas: canvas)

    let background = SheetColor(hex: "#FFFFFF") ?? .white
    let ink = background.blended(toward: background.contrastingInk, amount: 0.72)
    guard let context = CGContext(
        data: nil, width: Int(width), height: Int(height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { exit(1) }

    context.setFillColor(background.cgColor)
    context.fill(CGRect(origin: .zero, size: canvas))
    context.setFillColor(ink.cgColor)
    for cell in cells { context.fill(cell) }

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
              URL(fileURLWithPath: a[0]) as CFURL, UTType.png.identifier as CFString, 1, nil
          ) else { exit(1) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { exit(1) }

    let inset = cells.first.map { ($0.minX, $0.minY) } ?? (0, 0)
    let trailing = cells.last.map { (width - $0.maxX, height - $0.maxY) } ?? (0, 0)
    print(String(format: "%d cells, %.1f x %.1f each", cells.count,
                 cells.first?.width ?? 0, cells.first?.height ?? 0))
    print(String(format: "margins  left %.1f  top %.1f  right %.1f  bottom %.1f",
                 inset.0, inset.1, trailing.0, trailing.1))
    exit(0)
}

// ── does the ink land where the geometry says? ───────────────────────────────
//
// Step 6 of M5. Everything up to here is checked against arithmetic: the tests
// prove `pageTransform` maps rectangles exactly, and that the renderer fills
// the rectangles it is given. None of that proves the two are wired together,
// or that Quartz puts a photograph where the rectangle is. This renders a real
// sheet from real photographs through the real print path, rasterises the PDF
// at 300 ppi, finds each photograph's edges in the pixels, and compares them
// with the window's rectangles under the transform.
//
// Edges are found by rendering the same page twice — once with the
// photographs, once with background alone — and taking every pixel that
// differs. That is what makes the measurement work on a black sheet, where a
// photograph's dark edge is otherwise indistinguishable from the background.
// A row that happens to match the background exactly is still invisible, so
// the script reports the measured deviation rather than only a verdict.
//
//   photomancy-bench --verify-print <photo-folder> [--out <dir>]
if let flag = CommandLine.arguments.firstIndex(of: "--verify-print") {
    let rest = Array(CommandLine.arguments.dropFirst(flag + 1))
    guard let folder = rest.first(where: { !$0.hasPrefix("--") }) else {
        print("usage: --verify-print <photo-folder> [--out <dir>]")
        exit(2)
    }
    let outDirectory = rest.firstIndex(of: "--out").flatMap { index -> URL? in
        index + 1 < rest.count ? URL(fileURLWithPath: rest[index + 1]) : nil
    }

    let urls = Importer.expand([URL(fileURLWithPath: folder)])
    guard !urls.isEmpty else {
        print("no photographs in \(folder)")
        exit(2)
    }
    let resolver = BookmarkResolver()
    let references = urls.compactMap { try? Importer.makeReference(for: $0) }
    guard !references.isEmpty else {
        print("could not read any photograph in \(folder)")
        exit(2)
    }

    /// 300 ppi, as the plan sets the standard.
    let pixelsPerPoint = 300.0 / 72.0

    struct Configuration {
        let name: String
        let settings: SheetSettings
        let aspect: Double?
        let canvas: CGSize
    }

    let configurations = [
        Configuration(
            name: "5 × 4, gap 12, square, white",
            settings: SheetSettings(columns: 5, rows: 4, gap: 12, backgroundHex: "#FFFFFF"),
            aspect: 1, canvas: CGSize(width: 1600, height: 900)
        ),
        Configuration(
            name: "8 × 8, gap 1, square, white",
            settings: SheetSettings(columns: 8, rows: 8, gap: 1, backgroundHex: "#FFFFFF"),
            aspect: 1, canvas: CGSize(width: 1600, height: 900)
        ),
        Configuration(
            name: "3 × 2, gap 4, 3:2, black",
            settings: SheetSettings(columns: 3, rows: 2, gap: 4, backgroundHex: "#000000"),
            aspect: 1.5, canvas: CGSize(width: 1600, height: 900)
        ),
    ]

    /// The rasterised page, as sRGB bytes.
    func rasterise(_ pdf: Data, pageSize: CGSize) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider),
              let page = document.page(at: 1) else { return nil }
        let width = Int((pageSize.width * pixelsPerPoint).rounded())
        let height = Int((pageSize.height * pixelsPerPoint).rounded())
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return }
            context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
            context.drawPDFPage(page)
        }
        return (pixels, width, height)
    }

    var worstOverall = 0.0
    var failures = 0

    for configuration in configurations {
        let geometry = sheetGeometry(
            settings: configuration.settings,
            cellAspect: configuration.aspect,
            canvas: configuration.canvas
        )
        let paper = configuration.settings.paper
        let page = CGRect(origin: .zero, size: paper.points)
        let transform = pageTransform(from: geometry.block, onto: page)

        // As many photographs as the grid holds, repeating the folder only
        // because a test folder is smaller than an 8 × 8 sheet. The app never
        // repeats a photograph; here it is filler for a geometry measurement.
        var placements: [PrintImages.Placement] = []
        for cell in 0..<geometry.cells.count {
            placements.append(PrintImages.Placement(cell: cell, reference: references[cell % references.count]))
        }

        guard let frames = try? PrintImages.frames(
            for: placements, geometry: geometry, printable: page, resolver: resolver
        ) else {
            print("\(configuration.name): could not decode the originals")
            failures += 1
            continue
        }

        let background = configuration.settings.background
        let withPhotographs = SheetRenderer(geometry: geometry, background: background, frames: frames)
        let bare = SheetRenderer(geometry: geometry, background: background, frames: [])
        guard let inked = withPhotographs.pdf(pageSize: paper.points),
              let empty = bare.pdf(pageSize: paper.points),
              let a = rasterise(inked, pageSize: paper.points),
              let b = rasterise(empty, pageSize: paper.points) else {
            print("\(configuration.name): could not rasterise")
            failures += 1
            continue
        }

        if let outDirectory {
            try? FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
            let name = configuration.name.replacingOccurrences(of: " ", with: "-")
                .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "×", with: "x")
            try? inked.write(to: outDirectory.appendingPathComponent("\(name).pdf"))
        }

        /// Every pixel that the photographs put on the page.
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * a.width + x) * 4
            return abs(Int(a.pixels[offset]) - Int(b.pixels[offset])) > 8
                || abs(Int(a.pixels[offset + 1]) - Int(b.pixels[offset + 1])) > 8
                || abs(Int(a.pixels[offset + 2]) - Int(b.pixels[offset + 2])) > 8
        }

        var worst = 0.0
        var worstCell = -1
        var ambiguous = 0
        var expectedRects: [CGRect] = []

        for frame in frames {
            let cell = geometry.cells[frame.cell].applying(transform)
            let aspect = Double(frame.image.width) / Double(frame.image.height)
            let expected = fitted(aspectRatio: aspect, in: cell)
            expectedRects.append(expected)

            // In pixels, with y measured down the bitmap rather than up the page.
            let left = expected.minX * pixelsPerPoint
            let right = expected.maxX * pixelsPerPoint
            let top = (paper.points.height - expected.maxY) * pixelsPerPoint
            let bottom = (paper.points.height - expected.minY) * pixelsPerPoint

            // Search the cell, not a fixed margin around the photograph.
            //
            // A generous margin was the first attempt and it measured the
            // neighbours: at these gaps the next photograph is only a few
            // pixels away, so every cell reported an error the size of the
            // search window. A photograph is fitted inside its cell and cells
            // are a gap apart, so the cell plus one pixel cannot reach a
            // neighbour — and a photograph that missed its cell entirely
            // leaves no ink here, which is counted and reported.
            let cellLeft = cell.minX * pixelsPerPoint
            let cellRight = cell.maxX * pixelsPerPoint
            let cellTop = (paper.points.height - cell.maxY) * pixelsPerPoint
            let cellBottom = (paper.points.height - cell.minY) * pixelsPerPoint
            let x0 = max(0, Int(cellLeft) - 1), x1 = min(a.width - 1, Int(cellRight) + 1)
            let y0 = max(0, Int(cellTop) - 1), y1 = min(a.height - 1, Int(cellBottom) + 1)
            guard x0 <= x1, y0 <= y1 else { ambiguous += 1; continue }

            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for y in y0...y1 {
                for x in x0...x1 where isInk(x, y) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard minX <= maxX else {
                ambiguous += 1
                continue
            }

            // Ink fills whole pixels, so an edge at 100.4 lights pixel 100 and
            // the far edge at 200.6 lights pixel 200 — one pixel of slack in
            // each direction is the measurement, not an error. Quartz also
            // antialiases an image's edge, which can put a trace of ink one
            // pixel further out again. Measured floor on a correct render is
            // 1.3 px, which is 0.11 mm at 300 ppi; the gate below is set at 2
            // to sit above that, and NOT because anything needed loosening —
            // a displacement of half a point, 0.18 mm, measures 2.8 px here
            // and leaves thousands of stray pixels.
            let deviations = [
                abs(Double(minX) - left), abs(Double(maxX + 1) - right),
                abs(Double(minY) - top), abs(Double(maxY + 1) - bottom),
            ]
            if let cellWorst = deviations.max(), cellWorst > worst {
                worst = cellWorst
                worstCell = frame.cell
            }
        }

        // Nothing may be drawn outside the photographs' own rectangles: no
        // photograph overflowing its cell, no second copy anywhere, no ink in
        // a gap. Measured over the whole page, which is the half the per-cell
        // search cannot see.
        let allowed = expectedRects.map { rect -> (Int, Int, Int, Int) in
            (Int(rect.minX * pixelsPerPoint) - 1, Int(rect.maxX * pixelsPerPoint) + 1,
             Int((paper.points.height - rect.maxY) * pixelsPerPoint) - 1,
             Int((paper.points.height - rect.minY) * pixelsPerPoint) + 1)
        }
        var stray = 0
        for y in 0..<a.height {
            for x in 0..<a.width where isInk(x, y) {
                if !allowed.contains(where: { x >= $0.0 && x <= $0.1 && y >= $0.2 && y <= $0.3 }) {
                    stray += 1
                }
            }
        }

        worstOverall = max(worstOverall, worst)
        let ok = worst <= 2.0 && stray == 0
        if !ok { failures += 1 }
        let name = configuration.name.padding(toLength: 30, withPad: " ", startingAt: 0)
        let metrics = printMetrics(for: geometry, onto: page)
        print(String(
            format: "%@ %2d cells  cell %.1f × %.1f mm  worst edge %.2f px  stray %d  %@",
            name, frames.count,
            metrics?.cell.width ?? 0, metrics?.cell.height ?? 0,
            worst, stray, ok ? "ok" : "OFF"
        ))
        if worst > 2.0 { print("    worst at cell \(worstCell)") }
        if ambiguous > 0 { print("    \(ambiguous) photographs left no measurable ink — same colour as the sheet") }
    }

    print("")
    if failures == 0 {
        print(String(format: "PASS — every photograph within %.2f px of its rectangle at 300 ppi (%.3f mm), no stray ink",
                     worstOverall, worstOverall / 300 * 25.4))
        exit(0)
    }
    print(String(format: "FAIL — %d configurations off, worst %.2f px", failures, worstOverall))
    exit(1)
}

let options = parseOptions()
guard !options.paths.isEmpty else {
    print("usage: photomancy-bench <file-or-folder>... [--size N] [--count N]")
    exit(2)
}

let urls = Importer.expand(options.paths.map { URL(fileURLWithPath: $0) })
guard !urls.isEmpty else {
    print("no readable images under those paths")
    exit(1)
}

var byFormat: [String: [URL]] = [:]
for url in urls {
    guard let family = formatFamily(url) else { continue }
    byFormat[family, default: []].append(url)
}
// One sample per format, drawn once and reused for every size. Re-drawing per
// size would mean the sizes were measured on different photographs, and any
// comparison between them would be noise.
var sample: [String: [URL]] = [:]
for (family, files) in byFormat {
    sample[family] = Array(files.shuffled().prefix(options.count))
}

print("photomancy-bench — \(urls.count) images found, sampling up to \(options.count) per format")
print("host: \(ProcessInfo.processInfo.operatingSystemVersionString), \(ProcessInfo.processInfo.activeProcessorCount) cores")
print("")

for size in options.sizes {
    print("── decode to \(size) px on the long edge ─────────────────────────────")
    print(String(
        format: "%-6@ %5@ %9@ %9@ %9@ %9@ %9@ %8@",
        "fmt" as NSString, "n" as NSString, "median MB" as NSString,
        "cold p50" as NSString, "cold p90" as NSString,
        "warm p50" as NSString, "embed p50" as NSString, "embed n" as NSString
    ))
    var problems: [String] = []

    for family in ["JPEG", "HEIC", "PNG", "TIFF", "RAW", "other"] {
        guard let files = sample[family], !files.isEmpty else { continue }

        var cold: [Double] = []
        var warm: [Double] = []
        var embedded: [Double] = []
        var megabytes: [Double] = []
        var embeddedHits = 0
        var failures = 0

        for url in files {
            megabytes.append(Double(fileSize(url)) / 1_048_576)
            do {
                // First touch: nothing of this file is in the page cache unless
                // something else read it recently.
                cold.append(try milliseconds {
                    _ = try ThumbnailDecoder.decode(url: url, maxPixelSize: size, strategy: .fullDecode)
                })
                warm.append(try milliseconds {
                    _ = try ThumbnailDecoder.decode(url: url, maxPixelSize: size, strategy: .fullDecode)
                })
                var provenance = Thumbnail.Provenance.fullDecode
                embedded.append(try milliseconds {
                    provenance = try ThumbnailDecoder.decode(
                        url: url, maxPixelSize: size, strategy: .embeddedIfAdequate
                    ).provenance
                })
                if provenance == .embeddedPreview { embeddedHits += 1 }
            } catch {
                failures += 1
                if failures <= 3 {
                    problems.append("\(family): \(url.lastPathComponent) — \(error.localizedDescription)")
                }
            }
        }

        guard !cold.isEmpty else {
            print("\(family): all \(files.count) failed to decode")
            continue
        }
        print(String(
            format: "%-6@ %5d %9.1f %9.1f %9.1f %9.1f %9.1f %8@%@",
            family as NSString, cold.count,
            percentile(megabytes, 0.5),
            percentile(cold, 0.5), percentile(cold, 0.9),
            percentile(warm, 0.5), percentile(embedded, 0.5),
            "\(embeddedHits)/\(cold.count)" as NSString,
            (failures > 0 ? "  (\(failures) failed)" : "") as NSString
        ))
    }
    for problem in problems { print("   ! \(problem)") }
    print("")
}

// ── content hashing, which every import pays once ─────────────────────────────
print("── content hash (SHA-256, streaming) ────────────────────────────────────")
for family in ["JPEG", "HEIC", "PNG"] {
    guard let files = sample[family]?.prefix(20), !files.isEmpty else { continue }
    var times: [Double] = []
    var megabytes: [Double] = []
    for url in files {
        megabytes.append(Double(fileSize(url)) / 1_048_576)
        if let elapsed = try? milliseconds({ _ = try ContentHasher.hash(contentsOf: url) }) {
            times.append(elapsed)
        }
    }
    guard !times.isEmpty else { continue }
    let totalMB = megabytes.reduce(0, +)
    let totalSeconds = times.reduce(0, +) / 1000
    print(String(
        format: "%-6@ n=%-4d median %6.1f ms   %6.0f MB/s",
        family as NSString, times.count, percentile(times, 0.5),
        totalSeconds > 0 ? totalMB / totalSeconds : 0
    ))
}
print("")

// ── the real question: how long does a grid take to fill? ─────────────────────
let gridSize = 20
let gridSource = Array(urls.shuffled().prefix(gridSize))
if gridSource.count == gridSize {
    print("── filling a \(gridSize)-cell grid at 512 px, through the two-tier cache ──")

    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("photomancy-bench-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }

    let resolver = BookmarkResolver()
    let cache = ThumbnailCache(resolver: resolver, directory: temporary)

    var references: [PhotoReference] = []
    for url in gridSource {
        if let reference = try? Importer.makeReference(for: url) { references.append(reference) }
    }

    func fill() async -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        await withTaskGroup(of: Void.self) { group in
            for reference in references {
                group.addTask { _ = try? await cache.thumbnail(for: reference, maxPixel: 512) }
            }
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    let coldGrid = await fill()
    let statsAfterCold = cache.statistics
    cache.clearMemory()
    let diskGrid = await fill()
    let warmGrid = await fill()

    print(String(format: "cold  (decode from originals): %7.0f ms   [%d decoded]", coldGrid, statsAfterCold.decodes))
    print(String(format: "disk  (memory cleared)       : %7.0f ms", diskGrid))
    print(String(format: "warm  (in memory)            : %7.0f ms", warmGrid))
}
