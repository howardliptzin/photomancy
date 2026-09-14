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

    var body: some View {
        GeometryReader { proxy in
            let area = CGSize(
                width: max(1, proxy.size.width - 2 * Self.margin),
                height: max(1, proxy.size.height - 2 * Self.margin)
            )
            let pixels = ThumbnailSize.bucket(forCell: area, scale: displayScale)

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
                .frame(width: area.width, height: area.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)

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
