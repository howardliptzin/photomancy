import SwiftUI
import PhotomancyCore

/// One photograph in one cell.
///
/// Fit is the behaviour rather than a preference: the whole frame is shown with
/// background around it. Cropping is the photographer's decision and is out of
/// scope for this app.
struct SheetCell: View {

    let reference: PhotoReference
    let size: CGSize
    let background: SheetColor

    @Environment(LibraryController.self) private var controller
    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: Thumbnail?
    @State private var failure: String?

    /// The bucket for the whole cell, not one edge of it — under Fit a landscape
    /// frame spans the cell's width, and asking from the height alone would
    /// decode it too small.
    private var requestedPixels: Int {
        ThumbnailSize.bucket(forCell: size, scale: displayScale)
    }

    var body: some View {
        ZStack {
            if let thumbnail {
                Image(decorative: thumbnail.image, scale: displayScale)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failure != nil {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color(background.blended(toward: background.contrastingInk, amount: 0.45)))
            } else {
                // Stands in until the image arrives, derived from the background
                // so it reads on a dark sheet as well as a light one.
                Rectangle().fill(Color(background.placeholderTint))
            }
        }
        .help(failure ?? reference.displayName)
        .task(id: "\(reference.id.hex)@\(requestedPixels)") { await load() }
    }

    private func load() async {
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
