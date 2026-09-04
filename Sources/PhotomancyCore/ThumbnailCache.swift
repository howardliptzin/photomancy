import Foundation
import CoreGraphics
import os

/// The two-tier cache the grid reads through: memory, then disk, then a decode
/// at display size from the original.
///
/// Nothing in here touches the main thread, and nothing holds a full-resolution
/// image — that belongs only to the print path.
public final class ThumbnailCache: @unchecked Sendable {

    /// Which tier answered. Kept because it is the only way to tell a working
    /// bookmark from a warm disk cache: on a second launch, photographs render
    /// either way, and only one of those means the app actually works.
    public struct Statistics: Sendable, Equatable {
        public var memoryHits = 0
        public var diskHits = 0
        public var decodes = 0
        public var failures = 0
    }

    private struct State: Sendable {
        var inFlight: [String: Task<Thumbnail, any Error>] = [:]
        var statistics = Statistics()
    }

    private let resolver: BookmarkResolver
    private let disk: DiskThumbnailCache
    private let memory = NSCache<NSString, Thumbnail>()
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Bounded so a decode storm cannot spawn a thread per visible cell.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = max(2, ProcessInfo.processInfo.activeProcessorCount)
        queue.qualityOfService = .userInitiated
        queue.name = "\(AppPaths.bundleIdentifier).thumbnails"
        return queue
    }()

    public init(
        resolver: BookmarkResolver,
        directory: URL,
        memoryLimitBytes: Int = 256 * 1024 * 1024
    ) {
        self.resolver = resolver
        self.disk = DiskThumbnailCache(directory: directory)
        memory.totalCostLimit = memoryLimitBytes
    }

    public var statistics: Statistics {
        state.withLock { $0.statistics }
    }

    public func resetStatistics() {
        state.withLock { $0.statistics = Statistics() }
    }

    /// Synchronous, non-blocking. The grid calls this first so an already-warm
    /// cell draws in the same frame instead of flashing a placeholder.
    public func inMemory(_ reference: PhotoReference, maxPixel: Int) -> Thumbnail? {
        let pixels = ThumbnailSize.bucket(forPixels: maxPixel)
        return memory.object(forKey: Self.key(reference.id, pixels) as NSString)
    }

    public func thumbnail(for reference: PhotoReference, maxPixel: Int) async throws -> Thumbnail {
        let pixels = ThumbnailSize.bucket(forPixels: maxPixel)
        let key = Self.key(reference.id, pixels)

        if let cached = memory.object(forKey: key as NSString) {
            state.withLock { $0.statistics.memoryHits += 1 }
            return cached
        }

        // Twenty cells showing one photograph is one decode, not twenty.
        let task = state.withLock { state -> Task<Thumbnail, any Error> in
            if let existing = state.inFlight[key] { return existing }
            let created = Task<Thumbnail, any Error> { [self] in
                try await load(reference, pixels: pixels, key: key)
            }
            state.inFlight[key] = created
            return created
        }

        do {
            return try await task.value
        } catch {
            state.withLock { $0.statistics.failures += 1 }
            throw error
        }
    }

    public func clearMemory() {
        memory.removeAllObjects()
    }

    public func clearDisk() throws {
        try disk.removeAll()
    }

    public func diskEntryCount() -> Int {
        disk.entryCount()
    }

    // MARK: - Loading

    private func load(_ reference: PhotoReference, pixels: Int, key: String) async throws -> Thumbnail {
        defer { state.withLock { $0.inFlight[key] = nil } }

        let thumbnail = try await withCheckedThrowingContinuation { continuation in
            queue.addOperation { [self] in
                do {
                    continuation.resume(returning: try loadSynchronously(reference, pixels: pixels))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        memory.setObject(thumbnail, forKey: key as NSString, cost: thumbnail.byteCount)
        return thumbnail
    }

    /// Runs on the operation queue. Disk first, then the original.
    private func loadSynchronously(_ reference: PhotoReference, pixels: Int) throws -> Thumbnail {
        if let onDisk = disk.load(id: reference.id, pixels: pixels) {
            state.withLock { $0.statistics.diskHits += 1 }
            return onDisk
        }

        // The only place an original is opened, and it is opened inside the
        // bookmark's scope.
        let thumbnail = try resolver.withAccess(reference) { url in
            try ThumbnailDecoder.decode(url: url, maxPixelSize: pixels)
        }
        state.withLock { $0.statistics.decodes += 1 }
        disk.store(thumbnail, id: reference.id, pixels: pixels)
        return thumbnail
    }

    static func key(_ id: ContentHash, _ pixels: Int) -> String {
        "\(id.hex)@\(pixels)"
    }
}
