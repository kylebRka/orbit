import AppKit
import SwiftUI
import ApplicationServices
import ServiceManagement
import OrbitCore

@MainActor
final class AppModel: ObservableObject {
    @Published var file: FileInspection?
    @Published var inspecting = false
    @Published var busy = false
    @Published var result: URL?
    @Published var error: String?
    @Published var showingError = false
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var language = AppLanguage.current {
        didSet { UserDefaults.standard.set(language.rawValue,forKey:"orbitLanguage"); languageChanged?() }
    }
    @Published var history: [URL] = []
    @Published var gesturePaused = false
    @Published var accessibility = AXIsProcessTrusted()
    @Published var finderAllowed = UserDefaults.standard.bool(forKey:"finderEnabled")
    @Published var section = "convert"
    @Published var selectedFormat: OutputFormat?
    var showWindow: (() -> Void)?
    var showWheel: ((FileInspection) -> Void)?
    var permissionChanged: (() -> Void)?
    var languageChanged: (() -> Void)?
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
        inspecting = true; file = nil; selectedFormat = nil; error = nil; result = nil; showingError = false
        Task {
            do {
                let inspected = try await Task.detached(priority:.userInitiated) { try await ConversionEngine.inspect(url) }.value
                guard loadID == id else { return }
                file = inspected; selectedFormat = inspected.formats.first; inspecting = false
            } catch {
                guard loadID == id else { return }
                inspecting = false; reportError(error)
            }
        }
    }

    func convert(_ format: OutputFormat, file source: FileInspection? = nil, background:Bool = false) {
        guard !busy, let source = source ?? file else { return }
        run(source,format:format,background:background) { runner in
            try await ConversionEngine.convert(source,to:format,runner:runner)
        }
    }

    func trim(_ source:FileInspection, range:MediaRange, format:OutputFormat, muted:Bool) {
        run(source,format:format,background:true,closeEditor:true) { runner in
            try await MediaEditing.trim(source,range:range,format:format,muted:muted,runner:runner)
        }
    }

    private func run(_ source:FileInspection, format:OutputFormat, background:Bool, closeEditor:Bool = false,
                     operation:@escaping @Sendable (CommandRunner) async throws -> URL) {
        guard !busy else { return }
        loadID = UUID(); inspecting = false
        busy = true; result = nil; error = nil; showingError = false
        file = source; selectedFormat = source.formats.contains(format) ? format : source.formats.first
        let runner = CommandRunner(); self.runner = runner
        task = Task {
            do {
                try Task.checkCancellation()
                let worker = Task.detached(priority:.userInitiated) {
                    try await operation(runner)
                }
                let output = try await withTaskCancellationHandler(operation: {
                    try await worker.value
                }, onCancel: { worker.cancel(); runner.cancel() })
                if !Task.isCancelled { completed(output); if closeEditor { editor?.close() } }
            } catch is CancellationError {} catch { reportError(error,present:!background) }
            busy = false; self.runner = nil; task = nil
        }
    }

    func completed(_ output: URL) {
        result = output; history.insert(output, at:0); history = Array(history.prefix(10))
    }

    func presentLastError() { showWindow?(); showingError = error != nil }

    func reportError(_ error:Error,present:Bool = true) {
        self.error = error.localizedDescription
        showingError = present
    }

    func cancelAndWait() async { cancel(); await task?.value }
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
            catch { reportError(error) }
        }
    }

    func setLoginEnabled(_ enabled:Bool) {
        do {
            if enabled && SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled && SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch { loginStatus = SMAppService.mainApp.status; reportError(error) }
    }

    func refreshPermissions() {
        loginStatus = SMAppService.mainApp.status
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
