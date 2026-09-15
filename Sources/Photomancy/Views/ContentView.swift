import SwiftUI
import PhotomancyCore

struct ContentView: View {

    @Environment(LibraryController.self) private var controller
    @State private var isTargetedForDrop = false
    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        @Bindable var controller = controller

        NavigationSplitView {
            SidebarView(selection: $controller.selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            detail
        }
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            controller.importPhotographs(from: urls)
            return true
        } isTargeted: { targeted in
            isTargetedForDrop = targeted
        }
        .overlay {
            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(2)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        let photographs = controller.photographs
        if photographs.isEmpty {
            EmptyLibraryView()
        } else {
            SheetView()
                .safeAreaInset(edge: .bottom, spacing: 0) { SheetControls() }
            .task(id: photographs.count) {
                try? await Task.sleep(for: .seconds(2))
                controller.logCacheSummary()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            // All Photos is the union of the collections and has no name to change.
            if let id = controller.selection {
                TextField("Collection", text: collectionName(id))
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($titleFieldFocused)
                    .onChange(of: titleFieldFocused) { _, focused in
                        controller.isEditingText = focused
                    }
                    .onSubmit { titleFieldFocused = false }
                    .frame(minWidth: 120, idealWidth: 200)
            } else {
                Text("All Photos").font(.headline)
            }
        }
        ToolbarItem(placement: .navigation) {
            // Quiet, beside the title, because the shape belongs to the
            // collection. A derived shape says what it resolved to.
            if !controller.photographs.isEmpty {
                Menu {
                    Picker("Cell shape", selection: cellShape) {
                        Text(CellShape.derivedFromCollection.menuTitle(derivedAspect: controller.derivedAspect))
                            .tag(CellShape.derivedFromCollection)
                        Text("Square").tag(CellShape.square)
                        Text("3:2").tag(CellShape.threeByTwo)
                        Text("4:3").tag(CellShape.fourByThree)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(controller.cellShapeTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .fixedSize()
                .help("Cell shape")
            }
        }
        ToolbarItem(placement: .principal) {
            if let progress = controller.importProgress {
                HStack(spacing: 8) {
                    ProgressView(value: progress.fraction)
                        .frame(width: 110)
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            } else if let message = controller.message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                controller.presentImportPanel()
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .help("Import photographs (⌘I)")
        }
    }
}

extension ContentView {
    fileprivate var cellShape: Binding<CellShape> {
        Binding(get: { controller.cellShape }, set: { controller.cellShape = $0 })
    }

    fileprivate func collectionName(_ id: UUID) -> Binding<String> {
        Binding(
            get: { controller.store.document.collections.first { $0.id == id }?.name ?? "" },
            set: { controller.store.rename(id, to: $0) }
        )
    }
}

struct EmptyLibraryView: View {

    @Environment(LibraryController.self) private var controller

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drag photographs here")
                .font(.title3)
            Text(controller.selection == nil
                 ? "Or a folder of them. They go into a new collection. Selection happens now; the order is found by rolling."
                 : "Or a folder of them. Selection happens now; the order is found by rolling.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Import…") { controller.presentImportPanel() }
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
