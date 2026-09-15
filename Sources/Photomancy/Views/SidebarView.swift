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
                    .badge(controller.store.document.references.count)
                    .tag(Row.allPhotos)
            }

            if !controller.store.document.collections.isEmpty {
                Section("Collections") {
                    ForEach(controller.store.document.collections) { collection in
                        row(for: collection)
                            .tag(Row.collection(collection.id))
                    }
                }
            }
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
        }
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
                .badge(collection.memberIDs.count)
                // Double-click the name to rename it, as in Finder. Simultaneous,
                // so the list's own single-click selection is never held back
                // waiting to see whether a second click follows.
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    controller.renamingCollection = collection.id
                })
                .contextMenu {
                    Button("Rename") { controller.renamingCollection = collection.id }
                    Button("Delete Collection", role: .destructive) {
                        controller.deleteCollection(collection.id)
                    }
                }
        }
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
