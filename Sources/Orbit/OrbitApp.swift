import AppKit
import SwiftUI
import OrbitCore

@main
struct OrbitApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var gestures: GestureController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let content = MainView(model: model)
        window = NSWindow(contentRect: NSRect(x:0, y:0, width:940, height:670),
                          styleMask:[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing:.buffered, defer:false)
        window.title = "Orbit"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width:820, height:620)
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        model.showWindow = { [weak self] in self?.showWindow() }
        gestures = GestureController(model: model)
        model.showWheel = { [weak self] file in self?.gestures.present(file, at: NSEvent.mouseLocation, dragging:false) }
        model.permissionChanged = { [weak self] in self?.gestures.start() }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"circle.hexagongrid", accessibilityDescription:"Orbit")
        let menu = NSMenu()
        menu.addItem(withTitle:L("Open Orbit", "Открыть Orbit"), action:#selector(showWindow), keyEquivalent:"").target = self
        menu.addItem(withTitle:L("Choose file…", "Выбрать файл…"), action:#selector(chooseFile), keyEquivalent:"").target = self
        menu.addItem(.separator())
        let pause = NSMenuItem(title:L("Pause global gesture", "Приостановить глобальный жест"), action:#selector(togglePause(_:)), keyEquivalent:"")
        pause.target = self; menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(withTitle:L("Quit Orbit", "Завершить Orbit"), action:#selector(quit), keyEquivalent:"q").target = self
        statusItem.menu = menu
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle:L("About Orbit", "Об Orbit"), action:#selector(showWindow), keyEquivalent:"").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:L("Quit Orbit", "Завершить Orbit"), action:#selector(quit), keyEquivalent:"q").target = self
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:"Edit")
        for (name, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle:name, action:NSSelectorFromString(action), keyEquivalent:key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
        gestures.start()
        showWindow()
        if CommandLine.arguments.contains("--demo") { model.loadDemo() }
    }

    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    @objc func chooseFile() { showWindow(); model.chooseFile() }
    @objc func togglePause(_ sender: NSMenuItem) { model.gesturePaused.toggle(); sender.state = model.gesturePaused ? .on : .off }
    @objc func quit() { model.cancel(); NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        if let first = filenames.first { showWindow(); model.load(URL(fileURLWithPath:first)) }
        sender.reply(toOpenOrPrint:.success)
    }
}
