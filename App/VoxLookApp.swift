import SwiftUI
import UniformTypeIdentifiers
import VoxKit
import VoxRender

@main
struct VoxLookApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
    }
}

extension UTType {
    static let vox = UTType(importedAs: "com.ephtracy.vox")
}

struct ContentView: View {
    @State private var scene: VoxScene?
    @State private var fileName: String?
    @State private var error: String?
    @State private var importing = false
    @State private var targeted = false

    var body: some View {
        ZStack {
            if let scene {
                PreviewRepresentable(scene: scene)
                    .id(fileName)
            } else {
                welcome
            }
        }
        .navigationTitle(fileName ?? "VoxLook")
        .toolbar {
            Button("Open…", systemImage: "folder") { importing = true }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.vox, .data]) { result in
            if case .success(let url) = result { load(url) }
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in load(url) } }
            }
            return true
        }
        .onOpenURL { load($0) }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("VoxLook is installed")
                .font(.title2.weight(.semibold))
            Text("Select a MagicaVoxel `.vox` file in Finder and press Space.\nThumbnails show up in Finder icons automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let error {
                Text(error).foregroundStyle(.red)
            }
            HStack {
                Button("Open a .vox File…") { importing = true }
                    .keyboardShortcut("o")
                Button("Extension Settings…") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
            }
            .padding(.top, 6)
            Text("Or drop a file here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            scene = VoxScene(file: try VoxFile(contentsOf: url), interactive: true)
            fileName = url.lastPathComponent
            error = nil
        } catch {
            self.error = "\(url.lastPathComponent): \(error)"
        }
    }
}

private struct PreviewRepresentable: NSViewRepresentable {
    let scene: VoxScene
    func makeNSView(context: Context) -> VoxPreviewView { VoxPreviewView(scene: scene) }
    func updateNSView(_ view: VoxPreviewView, context: Context) {}
}
