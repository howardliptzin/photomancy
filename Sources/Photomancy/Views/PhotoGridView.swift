import SwiftUI
import PhotomancyCore

/// The import review grid — *not* the sheet.
///
/// The sheet is a true rows × columns page positioned from `layout()` in M2, and
/// it must never be a `LazyVGrid`: that geometry is invisible to the print path
/// and the two would drift. This view exists only so an import can be seen, and
/// it is expected to be deleted.
struct PhotoGridView: View {

    let photographs: [PhotoReference]

    @State private var cellSide: Double = 160

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSide, maximum: cellSide * 1.6), spacing: 12)],
                spacing: 12
            ) {
                ForEach(photographs) { reference in
                    ThumbnailCell(reference: reference, side: cellSide)
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Text("\(photographs.count) photographs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "photo").font(.caption2).foregroundStyle(.tertiary)
                Slider(value: $cellSide, in: 90...320).frame(width: 150)
                Image(systemName: "photo").font(.body).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
