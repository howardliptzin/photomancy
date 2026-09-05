import SwiftUI
import PhotomancyCore

@main
struct PhotomancyApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var controller = LibraryController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(controller)
                .task { controller.start() }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Photographs…") {
                    LibraryController.shared.presentImportPanel()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("New Collection") {
                    LibraryController.shared.newCollection()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // The native baseline for discovering the keyboard: every action is
            // a menu item carrying its own key equivalent. The menu owns these
            // outright, so a key is dispatched once no matter what has focus.
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Arrangement") { LibraryController.shared.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!LibraryController.shared.canUndo)
                Button("Redo Arrangement") { LibraryController.shared.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!LibraryController.shared.canRedo)
            }

            CommandMenu("Sheet") {
                Button("Randomize") { LibraryController.shared.randomize() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Pin or Unpin") {
                    LibraryController.shared.togglePin(at: LibraryController.shared.focusedCell)
                }
                .keyboardShortcut("p", modifiers: [])
                Divider()
                Button("Reset") { LibraryController.shared.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("Keyboard Shortcuts") { LibraryController.shared.showingShortcuts.toggle() }
                    .keyboardShortcut("?", modifiers: [])
            }
        }
    }
}

/// Exists for one reason: `application(_:open:)`.
///
/// Files opened through Finder, "Open With", a drop on the Dock icon or
/// `open -a Photomancy …` carry the same user-selected permission the file
/// picker grants, and are therefore bookmarkable. Routing them here makes those
/// a first-class import path rather than a dead end.
final class AppDelegate: NSObject, NSApplicationDelegate {

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            LibraryController.shared.importPhotographs(from: urls)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            // The debounced save must not be the reason a bookmark is lost.
            LibraryController.shared.store.saveNow()
        }
    }
}
