import SwiftUI
import PhotomancyCore

struct SidebarView: View {

    @Environment(LibraryController.self) private var controller
    @Binding var selection: UUID?

    @FocusState private var renameFieldFocused: Bool

    /// A row in the sidebar.
    ///
    /// Not `UUID?`. A `List` reads a `nil` selection as "nothing selected", so a
    /// row tagged `nil` could never be chosen — which is why All Photos did
    /// nothing when clicked. Every row needs a real value.
    private enum Row: Hashable {
        case allPhotos
        case collection(UUID)
    }

    /// Rows onto the controller's selection, where `nil` is still All Photos.
    ///
    /// Writes only a real change: the selection resets the sheet and its history
    /// whenever it is assigned, so re-clicking the open row must not re-roll it.
    /// A click in empty space deselects nothing — something is always open.
    private var rowSelection: Binding<Row?> {
        Binding(
            get: { selection.map(Row.collection) ?? .allPhotos },
            set: { row in
                let chosen: UUID?
                switch row {
                case .allPhotos: chosen = nil
                case .collection(let id): chosen = id
                case nil: return
                }
                if chosen != selection { selection = chosen }
            }
        )
    }

    var body: some View {
        @Bindable var controller = controller

        List(selection: rowSelection) {
            Section {
                Label("All Photos", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dropZone(.allPhotos, in: controller.dropZones)
                    .badge(controller.store.document.references.count)
                    .tag(Row.allPhotos)
            }

            if !controller.store.document.collections.isEmpty {
                Section("Collections") {
                    ForEach(controller.store.document.collections) { collection in
                        row(for: collection)
                            .dropZone(.collection(collection.id), in: controller.dropZones)
                            .tag(Row.collection(collection.id))
                    }
                }
            }
        }
        // The list's own menu and double-click, not gestures on the rows. A tap
        // gesture on a row — even a simultaneous one — swallows the click the
        // list selects with, and the sidebar stops changing collections.
        .contextMenu(forSelectionType: Row.self) { rows in
            if let id = collectionID(in: rows) {
                Button("Rename") { controller.renamingCollection = id }
                Button("Delete Collection", role: .destructive) { controller.deleteCollection(id) }
            }
        } primaryAction: { rows in
            // Double-click a collection to rename it, as in Finder.
            if let id = collectionID(in: rows) { controller.renamingCollection = id }
        }
        .onChange(of: renameFieldFocused) { _, focused in
            controller.isEditingText = focused
            if !focused { controller.renamingCollection = nil }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                controller.newCollection()
            } label: {
                Label("New Collection", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // Photographs dragged here, or onto any empty space in the sidebar,
            // go into a new collection; the button says so while they are over it.
            .background(dropHighlight(controller.sidebarDrop == .newCollection))
        }
        .dropZone(.sidebar, in: controller.dropZones)
    }

    @ViewBuilder
    private func row(for collection: PhotoCollection) -> some View {
        if controller.renamingCollection == collection.id {
            TextField("Name", text: name(of: collection))
                .textFieldStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                // The selected row is drawn in the accent colour, and a field with
                // no ground of its own put thin dark type straight onto that blue —
                // illegible. A white ground, and light-mode text on it whatever the
                // system appearance, so it reads in dark mode too.
                .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                .environment(\.colorScheme, .light)
                .focused($renameFieldFocused)
                .onSubmit { controller.renamingCollection = nil }
                .onExitCommand { controller.renamingCollection = nil }
                .task { renameFieldFocused = true }
        } else {
            Label(collection.name, systemImage: "rectangle.stack")
                .frame(maxWidth: .infinity, alignment: .leading)
                // Photographs dragged out of the sheet and held over this row go
                // here when dropped.
                .background(dropHighlight(controller.sidebarDrop == .collection(collection.id)))
                .badge(collection.memberIDs.count)
        }
    }

    /// The accent, faint, a little larger than the label it sits behind so it
    /// reads as the row.
    private func dropHighlight(_ active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(active ? 0.28 : 0))
            .padding(.horizontal, -6)
            .padding(.vertical, -3)
            .allowsHitTesting(false)
    }

    /// A single collection, or `nil` — All Photos has no name to change and
    /// cannot be deleted.
    private func collectionID(in rows: Set<Row>) -> UUID? {
        guard rows.count == 1, case .collection(let id)? = rows.first else { return nil }
        return id
    }

    /// Writes straight through to the store, so a rename is saved as it is typed
    /// rather than only when the field is committed.
    private func name(of collection: PhotoCollection) -> Binding<String> {
        Binding(
            get: {
                controller.store.document.collections
                    .first { $0.id == collection.id }?.name ?? collection.name
            },
            set: { controller.store.rename(collection.id, to: $0) }
        )
    }
}
