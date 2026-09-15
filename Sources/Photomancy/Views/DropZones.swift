import SwiftUI
import AppKit
import PhotomancyCore

/// Where the sidebar's drop targets are, for photographs dragged out of the
/// sheet.
///
/// The sheet's drag is a SwiftUI gesture, and SwiftUI coordinates do not cross
/// from the detail column to the sidebar: each column is its own hosting view.
/// So each target carries a small AppKit view, and its frame is read in window
/// coordinates only when a drag asks — never cached, so scrolling the list or
/// collapsing the sidebar cannot leave a stale rectangle behind.
@MainActor
final class DropZones {

    /// No zone for the New Collection button. Measured inside the sidebar's
    /// bottom inset, its reader came back the size of the whole sidebar, and
    /// every drop became a new collection. It sits below the rows, where empty
    /// space already means a new collection, so it needs no zone of its own.
    enum Zone: Hashable {
        case sidebar
        case allPhotos
        case collection(UUID)
    }

    private final class Entry {
        weak var view: NSView?
        init(_ view: NSView) { self.view = view }
    }

    private var entries: [Zone: Entry] = [:]

    /// A measured label is shorter than its row; this much above and below
    /// covers the row's own padding, so moving between rows never reads as
    /// empty space.
    private static let rowSlack: CGFloat = 6

    fileprivate func register(_ view: NSView, as zone: Zone) {
        // Rows are reused as the list changes, so a view may now stand for a
        // different collection than it did.
        for (key, entry) in entries where key != zone && entry.view === view {
            entries[key] = nil
        }
        if entries[zone]?.view !== view { entries[zone] = Entry(view) }
    }

    /// What a drop at this point — in window coordinates, from the drag's own
    /// event — would do. `nil` off the sidebar.
    func drop(atWindowPoint point: CGPoint, in window: NSWindow, source: UUID?) -> SidebarDrop? {
        guard let sidebar = frame(of: .sidebar, in: window) else { return nil }
        let rows = entries.keys.compactMap { zone -> (id: UUID, frame: CGRect)? in
            guard case .collection(let id) = zone, let frame = frame(of: zone, in: window) else { return nil }
            return (id, frame)
        }
        return SidebarDrop.resolve(
            point,
            sidebar: sidebar,
            allPhotosRow: frame(of: .allPhotos, in: window),
            collectionRows: rows,
            source: source,
            slack: Self.rowSlack
        )
    }

    /// The visible part only: a row scrolled out of the list is not a target.
    private func frame(of zone: Zone, in window: NSWindow) -> CGRect? {
        guard let view = entries[zone]?.view, view.window === window,
              !view.isHiddenOrHasHiddenAncestor else { return nil }
        let visible = view.visibleRect
        guard !visible.isEmpty else { return nil }
        return view.convert(visible, to: nil)
    }
}

extension View {
    /// Marks this view as a place photographs can be dropped. Adds no gesture and
    /// takes no clicks, so a list row keeps selecting as it did.
    func dropZone(_ zone: DropZones.Zone, in zones: DropZones) -> some View {
        background(DropZoneReader(zones: zones, zone: zone))
    }
}

private struct DropZoneReader: NSViewRepresentable {
    let zones: DropZones
    let zone: DropZones.Zone

    func makeNSView(context: Context) -> PassThroughView {
        let view = PassThroughView()
        zones.register(view, as: zone)
        return view
    }

    func updateNSView(_ view: PassThroughView, context: Context) {
        zones.register(view, as: zone)
    }
}

/// Invisible to the pointer. A view that answered hit-tests would sit on top of
/// the row and swallow the click the list selects with.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
