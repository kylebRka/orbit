import AppKit
import SwiftUI
import ApplicationServices
import OrbitCore

@MainActor
final class AppModel: ObservableObject {
    @Published var file: FileInspection?
    @Published var inspecting = false
    @Published var busy = false
    @Published var result: URL?
    @Published var error: String?
    @Published var history: [URL] = []
    @Published var gesturePaused = false
    @Published var accessibility = AXIsProcessTrusted()
    @Published var finderAllowed = UserDefaults.standard.bool(forKey:"finderEnabled")
    @Published var section = "convert"
    @Published var selectedFormat: OutputFormat?
    var showWindow: (() -> Void)?
    var showWheel: ((FileInspection) -> Void)?
    var permissionChanged: (() -> Void)?
    var editor: NSWindow?
    private var task: Task<Void, Never>?
    private var loadID = UUID()
    private var runner: CommandRunner?

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.prompt = L("Choose", "Выбрать")
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        guard !busy else { return }
        let id = UUID(); loadID = id
        inspecting = true; error = nil; result = nil
        Task {
            do {
                let inspected = try await Task.detached(priority:.userInitiated) { try await ConversionEngine.inspect(url) }.value
                guard loadID == id else { return }
                file = inspected; selectedFormat = inspected.formats.first; inspecting = false
            } catch {
                guard loadID == id else { return }
                inspecting = false; self.error = error.localizedDescription
            }
        }
    }

    func convert(_ format: OutputFormat, file source: FileInspection? = nil) {
        guard !busy, let source = source ?? file else { return }
        busy = true; result = nil; error = nil
        file = source; selectedFormat = format
        let runner = CommandRunner(); self.runner = runner
        task = Task {
            do {
                let worker = Task.detached(priority:.userInitiated) {
                    try await ConversionEngine.convert(source, to:format, runner:runner)
                }
                let output = try await withTaskCancellationHandler(operation: {
                    try await worker.value
                }, onCancel: { worker.cancel(); runner.cancel() })
                if !Task.isCancelled { completed(output) }
            } catch is CancellationError {} catch { self.error = error.localizedDescription; showWindow?() }
            busy = false; self.runner = nil; task = nil
        }
    }

    func completed(_ output: URL) {
        result = output; history.insert(output, at:0); history = Array(history.prefix(10))
        showWindow?()
    }

    func cancel() { runner?.cancel(); task?.cancel() }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options)
        permissionChanged?()
    }

    func requestFinder() {
        Task {
            do { _ = try await FinderSelection.read(); finderAllowed = true; UserDefaults.standard.set(true,forKey:"finderEnabled") }
            catch { self.error = error.localizedDescription }
        }
    }

    func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        permissionChanged?()
    }

    func loadDemo() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Orbit Sample.png")
        let image = NSImage(size:NSSize(width:900, height:600))
        image.lockFocus()
        NSGradient(starting:NSColor.systemBlue, ending:NSColor.systemCyan)!.draw(in:NSRect(x:0,y:0,width:900,height:600), angle:35)
        let mark = NSImage(systemSymbolName:"mountain.2.fill", accessibilityDescription:nil)!
        NSColor.white.set(); mark.draw(in:NSRect(x:200,y:120,width:500,height:350))
        image.unlockFocus()
        if let rep = NSBitmapImageRep(data:image.tiffRepresentation!), let data = rep.representation(using:.png, properties:[:]) {
            try? data.write(to:url); load(url)
        }
    }
}

enum FinderSelection {
    static func read() async throws -> [URL] {
        try await Task.detached(priority:.userInitiated) {
            // No filename is interpolated into executable AppleScript source.
            let script = NSAppleScript(source:"""
                tell application "Finder"
                    set paths to {}
                    repeat with itemRef in (selection as alias list)
                        set end of paths to POSIX path of itemRef
                    end repeat
                    return paths
                end tell
                """)!
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if error != nil { throw OrbitError.message(L("Allow Orbit to read the Finder selection in System Settings → Privacy & Security → Automation.", "Разрешите Orbit читать выделение Finder: Системные настройки → Конфиденциальность и безопасность → Автоматизация.")) }
            guard result.numberOfItems > 0 else { return [] }
            return (1...result.numberOfItems).compactMap { result.atIndex($0)?.stringValue }.map { URL(fileURLWithPath:$0) }
        }.value
    }
}
