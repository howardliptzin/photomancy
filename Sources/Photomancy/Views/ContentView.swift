import SwiftUI
import PhotomancyCore

struct ContentView: View {

    @Environment(LibraryController.self) private var controller
    @State private var isTargetedForDrop = false

    var body: some View {
        @Bindable var controller = controller

        NavigationSplitView {
            SidebarView(selection: $controller.selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 300)
        } detail: {
            detail
        }
        .navigationTitle(controller.currentTitle)
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
            SheetView(
                photographs: photographs,
                settings: controller.settings,
                cellAspect: controller.cellAspect
            )
            .safeAreaInset(edge: .bottom, spacing: 0) { SheetControls() }
            .task(id: photographs.count) {
                try? await Task.sleep(for: .seconds(2))
                controller.logCacheSummary()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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

struct EmptyLibraryView: View {

    @Environment(LibraryController.self) private var controller

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Drag photographs here")
                .font(.title3)
            Text("Or a folder of them. Curation happens now — after this, chance takes over.")
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
