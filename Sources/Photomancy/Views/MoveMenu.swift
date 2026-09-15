import SwiftUI
import PhotomancyCore

/// "Move to ▸" — or "Add to ▸" in All Photos — listing the collections, with
/// New Collection at the top, as Photos and Mail do. A submenu rather than a
/// dialog: the choice is one of a short list, and picking it is the whole act.
///
/// One view for the Edit menu and the right-click menu on a photograph, so the
/// two cannot drift. The controller is passed in because menu commands have no
/// environment.
struct MoveMenu: View {

    let controller: LibraryController
    /// Set from the right-click menu: the photograph that was clicked, which the
    /// menu acts on alone when it is not part of the selection.
    var cell: Int?

    var body: some View {
        Menu(controller.moveMenuTitle) {
            Button("New Collection") {
                target()
                controller.moveSelectedPhotographsToNewCollection()
            }
            .keyboardShortcut("n", modifiers: [.control, .command])

            let destinations = controller.moveDestinations
            if !destinations.isEmpty { Divider() }
            ForEach(destinations) { collection in
                Button(collection.name) {
                    target()
                    controller.moveSelectedPhotographs(to: collection.id)
                }
            }
        }
    }

    private func target() {
        if let cell { controller.targetForContextMenu(cell: cell) }
    }
}
