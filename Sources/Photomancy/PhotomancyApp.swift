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
                Button(LibraryController.shared.undoTitle) { LibraryController.shared.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!LibraryController.shared.canUndo)
                Button(LibraryController.shared.redoTitle) { LibraryController.shared.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!LibraryController.shared.canRedo)
            }

            // Cut, copy, paste and select all are gone — nothing responds to
            // them. Delete does, so it belongs here, where anyone would look.
            // Two items rather than one contextual title or a dialog: both
            // outcomes are named, both are one keystroke, and neither needs
            // dismissing. Removing from a collection is the frequent, reversible
            // one and gets the bare key.
            CommandGroup(replacing: .pasteboard) {
                Button("Remove from Collection") {
                    LibraryController.shared.removeSelectedFromCollection()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(
                    LibraryController.shared.selection == nil
                        || LibraryController.shared.selectedReference == nil
                        || LibraryController.shared.isEditingText
                )

                Button("Delete from Photomancy") {
                    LibraryController.shared.deleteSelectedFromLibrary()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(
                    LibraryController.shared.selectedReference == nil
                        || LibraryController.shared.isEditingText
                )
            }

            CommandMenu("Sheet") {
                Button("Randomize") { LibraryController.shared.randomize() }
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(LibraryController.shared.isEditingText)
                Button("Pin or Unpin") {
                    guard let cell = LibraryController.shared.selectedCell else { return }
                    LibraryController.shared.togglePin(at: cell)
                }
                .keyboardShortcut("p", modifiers: [])
                .disabled(LibraryController.shared.isEditingText)
                Divider()
                Button("Reset") { LibraryController.shared.reset() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Rename Collection…") {
                    LibraryController.shared.beginRenamingSelectedCollection()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(LibraryController.shared.selection == nil)
                Divider()
                Button("Keyboard Shortcuts") { LibraryController.shared.showingShortcuts.toggle() }
                    .keyboardShortcut("?", modifiers: [])
                    .disabled(LibraryController.shared.isEditingText)
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
