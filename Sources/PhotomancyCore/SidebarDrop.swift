import Foundation

/// What dropping photographs dragged out of the sheet would do, at one point
/// over the sidebar.
///
/// Pure, so the rule can be tested without a window: the app measures where the
/// sidebar and its rows are, and asks here.
public enum SidebarDrop: Hashable, Sendable {
    /// Into this collection — moved from a collection, added from All Photos.
    case collection(UUID)
    /// Into a collection made for them.
    case newCollection
    /// Over the sidebar, but somewhere a drop means nothing: All Photos, which
    /// holds nothing of its own, or the collection the photographs came from.
    case refused

    /// `nil` when the point is not over the sidebar at all — the drag is still
    /// the sheet's business.
    ///
    /// Rows are matched by height alone, grown by `slack` above and below: a
    /// row's measured frame is its label, narrower and shorter than the row the
    /// person sees, and a pointer passing between two rows must not flicker to
    /// "new collection". Where grown rows overlap, the nearest wins.
    ///
    /// Everywhere else in the sidebar makes a new collection — the space below
    /// the rows, and the New Collection button, which sits there. It is the one
    /// place nothing else is.
    ///
    /// Rectangles only have to share one coordinate space with the point.
    public static func resolve(
        _ point: CGPoint,
        sidebar: CGRect,
        allPhotosRow: CGRect?,
        collectionRows: [(id: UUID, frame: CGRect)],
        source: UUID?,
        slack: CGFloat = 0
    ) -> SidebarDrop? {
        guard sidebar.contains(point) else { return nil }

        var candidates: [(drop: SidebarDrop, distance: CGFloat)] = []
        if let allPhotosRow, spans(allPhotosRow, point.y, slack: slack) {
            candidates.append((.refused, abs(allPhotosRow.midY - point.y)))
        }
        for row in collectionRows where spans(row.frame, point.y, slack: slack) {
            candidates.append((row.id == source ? .refused : .collection(row.id), abs(row.frame.midY - point.y)))
        }
        return candidates.min(by: { $0.distance < $1.distance })?.drop ?? .newCollection
    }

    private static func spans(_ frame: CGRect, _ y: CGFloat, slack: CGFloat) -> Bool {
        y >= frame.minY - slack && y < frame.maxY + slack
    }
}
