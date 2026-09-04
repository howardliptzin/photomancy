import SwiftUI
import PhotomancyCore

struct SidebarView: View {

    @Environment(LibraryController.self) private var controller
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("All Photos", systemImage: "square.grid.2x2")
                    .badge(controller.store.document.references.count)
                    .tag(UUID?.none)
            }

            if !controller.store.document.collections.isEmpty {
                Section("Collections") {
                    ForEach(controller.store.document.collections) { collection in
                        Label(collection.name, systemImage: "rectangle.stack")
                            .badge(collection.memberIDs.count)
                            .tag(UUID?.some(collection.id))
                            .contextMenu {
                                Button("Delete Collection", role: .destructive) {
                                    controller.store.removeCollection(collection.id)
                                    if selection == collection.id { selection = nil }
                                }
                            }
                    }
                }
            }
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
}
