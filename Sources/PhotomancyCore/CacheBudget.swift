import Foundation
import CoreGraphics

/// How much decoded image the sheet is worth holding in memory.
///
/// **A function of the window's area, never a constant.** The 256 MB this
/// replaces was not wrong so much as accidental: it happens to fit a 5K window
/// and would not fit the next display, and on a small window it holds far more
/// than anything will ever ask for. The window is what decides the answer,
/// because the window is what the cells tile.
///
/// ## Where the number comes from
///
/// Cells tile the sheet, so the decoded total tracks the window's *area* and not
/// the number of cells: more cells simply means smaller ones. For one cell:
///
/// - A thumbnail is decoded to a **bucket** on the ladder, not to the exact cell
///   size, so that dragging a window does not re-decode the library at every
///   intermediate width. The ladder steps by 1.5× at worst, so a bucket can be
///   up to 1.5 times the cell's long edge — **2.25× the area**.
/// - Four bytes a pixel, decoded.
/// - A cell's bucket is its **long** edge, and under Fit the photograph is
///   inset inside the cell, so the decoded image is at most the square of that
///   long edge. For square cells that equals the cell's area; for an oblong cell
///   it is more, and for the usual ratios not by much.
///
/// That gives roughly `4 × 2.25 = 9` bytes per pixel of window for the sheet.
/// The lightbox is then one further image, decoded for its own drawn size and so
/// no larger than the window itself: another 4 bytes per pixel.
///
/// Thirteen bytes per window pixel — about 190 MB for a 5K window, 25 MB for a
/// 1280 × 800 one. The old constant was seven times too generous for the latter.
public enum CacheBudget {

    /// Decoded, always four bytes.
    static let bytesPerPixel = 4.0

    /// The worst a bucket overshoots a cell: the ladder's largest step, squared.
    static let bucketHeadroom = 2.25

    /// One lightbox image, which is never larger than the window it is drawn in.
    static let lightboxImages = 1.0

    /// Small windows still get a cache worth having.
    ///
    /// Not a floor on correctness — the arithmetic above is right at any size —
    /// but on thrashing: a 400 × 300 window derives 1.4 MB, and re-decoding a
    /// handful of thumbnails on every roll costs more than the memory saved.
    /// 64 MB is about a second of decoding, which is the thing actually being
    /// bought.
    public static let minimumBytes = 64 * 1024 * 1024

    /// A sanity bound, not a policy one. Nothing caps the grid, and nothing here
    /// caps the window either — this only stops a nonsense size from asking for
    /// a nonsense cache.
    public static let maximumBytes = 2 * 1024 * 1024 * 1024

    /// The memory cache's limit, in bytes, for a sheet of this size.
    ///
    /// - Parameters:
    ///   - size: The sheet, in points — the window, as the app thinks of it.
    ///   - scale: The display's backing scale. Points are not pixels, and a
    ///     Retina window holds four times the pixels of its size in points,
    ///     which is exactly the mistake this function exists to avoid making.
    public static func memoryLimit(forSheet size: CGSize, scale: Double) -> Int {
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              scale.isFinite, scale >= 1
        else { return minimumBytes }

        let pixels = Double(size.width) * Double(size.height) * scale * scale
        let perPixel = bytesPerPixel * bucketHeadroom + bytesPerPixel * lightboxImages
        let bytes = pixels * perPixel

        guard bytes.isFinite else { return minimumBytes }
        return min(max(Int(bytes), minimumBytes), maximumBytes)
    }
}
