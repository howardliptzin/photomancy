import SwiftUI
import PhotomancyCore

struct ThumbnailCell: View {

    let reference: PhotoReference
    let side: Double

    @Environment(LibraryController.self) private var controller
    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: Thumbnail?
    @State private var failure: String?

    /// The bucket, not the exact size — so nudging a window does not re-decode.
    private var requestedPixels: Int {
        ThumbnailSize.bucket(forPoints: side, scale: displayScale)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(.quaternary)

            if let thumbnail {
                Image(decorative: thumbnail.image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failure != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: side)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .help(failure ?? reference.displayName)
        .task(id: taskIdentity) { await load() }
    }

    private var taskIdentity: String {
        "\(reference.id.hex)@\(requestedPixels)"
    }

    private func load() async {
        // Already warm: draw in this frame rather than flashing a placeholder.
        if let warm = controller.cache.inMemory(reference, maxPixel: requestedPixels) {
            thumbnail = warm
            failure = nil
            return
        }
        do {
            thumbnail = try await controller.cache.thumbnail(for: reference, maxPixel: requestedPixels)
            failure = nil
        } catch {
            thumbnail = nil
            failure = error.localizedDescription
        }
    }
}
