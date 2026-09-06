import SwiftUI
import PhotomancyCore

struct SidebarView: View {

    @Environment(LibraryController.self) private var controller
    @Binding var selection: UUID?

    @FocusState private var renameFieldFocused: Bool

    var body: some View {
        @Bindable var controller = controller

        List(selection: $selection) {
            Section {
                Label("All Photos", systemImage: "square.grid.2x2")
                    .badge(controller.store.document.references.count)
                    .tag(UUID?.none)
            }

            if !controller.store.document.collections.isEmpty {
                Section("Collections") {
                    ForEach(controller.store.document.collections) { collection in
                        row(for: collection)
                            .tag(UUID?.some(collection.id))
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
                .textFieldStyle(.roundedBorder)
                .focused($renameFieldFocused)
                .onSubmit { controller.renamingCollection = nil }
                .onExitCommand { controller.renamingCollection = nil }
                .task { renameFieldFocused = true }
        } else {
            Label(collection.name, systemImage: "rectangle.stack")
                .badge(collection.memberIDs.count)
                .contextMenu {
                    Button("Rename") { controller.renamingCollection = collection.id }
                    Button("Delete Collection", role: .destructive) {
                        controller.store.removeCollection(collection.id)
                        if selection == collection.id { selection = nil }
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
