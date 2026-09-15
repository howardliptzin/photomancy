import SwiftUI
import PhotomancyCore

/// One photograph, as large as the window allows. Double-click, or Return.
///
/// The photograph shown is the selected cell, so everything that acts on a
/// selection — pinning, removing, deleting — acts on it through the same menu
/// items as on the sheet. The view only draws.
struct LightboxView: View {

    let reference: PhotoReference
    let isPinned: Bool
    let background: SheetColor
    let close: () -> Void

    @Environment(LibraryController.self) private var controller
    @Environment(\.displayScale) private var displayScale

    @State private var thumbnail: Thumbnail?
    @State private var shown: ContentHash?
    @State private var failure: String?

    private static let margin: CGFloat = 24
    /// The filename's line, and the space between it and the photograph.
    private static let captionHeight: CGFloat = 16
    private static let captionGap: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let area = CGRect(
                x: Self.margin,
                y: Self.margin,
                width: max(1, proxy.size.width - 2 * Self.margin),
                height: max(1, proxy.size.height - 2 * Self.margin - Self.captionGap - Self.captionHeight)
            )
            // Fitted, but a small original stays at its real size.
            let frame = lightboxFrame(
                pixelWidth: reference.pixelWidth,
                pixelHeight: reference.pixelHeight,
                in: area,
                scale: displayScale
            )
            let pixels = ThumbnailSize.bucket(
                forPhotograph: frame.size,
                originalLongEdge: max(reference.pixelWidth, reference.pixelHeight),
                scale: displayScale
            )

            ZStack(alignment: .topLeading) {
                Color(background)

                Group {
                    if let thumbnail {
                        Image(decorative: thumbnail.image, scale: displayScale)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else if failure != nil {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(Color(background.blended(toward: background.contrastingInk, amount: 0.45)))
                    }
                }
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

                // The file's name, centred under the photograph and following
                // it, so a small original keeps its name beside it rather than at
                // the foot of the window. Essential rather than decoration:
                // reviewing often means choosing between near-identical frames,
                // and the name is what tells them apart and what carries the
                // choice out of the app. Nothing is written on the sheet or paper.
                Text(reference.displayName)
                    .font(.caption)
                    .foregroundStyle(Color(background.captionInk))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: area.width, height: Self.captionHeight)
                    .position(x: area.midX, y: frame.maxY + Self.captionGap + Self.captionHeight / 2)

                // Anchored to the area, as it is anchored to the cell on the
                // sheet: the lightbox is one large cell.
                if isPinned {
                    PinMark().padding(Self.margin + 6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: close)
            .help(failure ?? reference.displayName)
            .task(id: "\(reference.id.hex)@\(pixels)") { await load(pixels) }
        }
    }

    private func load(_ pixels: Int) async {
        // Stepping to another photograph must not leave the last one on screen
        // while the next decodes. Whatever the sheet already holds of it shows
        // at once, soft, until the window-sized decode arrives — nothing
        // perceptibly waits, and nothing shows the wrong frame.
        if shown != reference.id {
            shown = reference.id
            failure = nil
            thumbnail = ThumbnailSize.ladder.reversed().lazy
                .compactMap { controller.cache.inMemory(reference, maxPixel: $0) }
                .first
        }
        if let warm = controller.cache.inMemory(reference, maxPixel: pixels) {
            thumbnail = warm
            return
        }
        do {
            let decoded = try await controller.cache.thumbnail(for: reference, maxPixel: pixels)
            guard shown == reference.id else { return }
            thumbnail = decoded
        } catch {
            guard thumbnail == nil else { return }
            failure = error.localizedDescription
        }
    }
}
