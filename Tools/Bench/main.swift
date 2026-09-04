import Foundation
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
