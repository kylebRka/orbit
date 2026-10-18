import AppKit
import SwiftUI
import Combine
import Carbon
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
final class AppDelegate:NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window:NSWindow!
    var statusItem:NSStatusItem!
    var gestures:GestureController!
    private var statusObservation:AnyCancellable?
    private var startedAtLogin = false

    static func isLoginLaunch(_ event:NSAppleEventDescriptor?) -> Bool {
        guard event?.eventID == kAEOpenApplication else { return false }
        return event?.paramDescriptor(forKeyword:keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem ||
            event?.paramDescriptor(forKeyword:keyAELaunchedAsLogInItem)?.booleanValue == true
    }

    func applicationWillFinishLaunching(_ notification:Notification) {
        startedAtLogin = Self.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    func applicationDidFinishLaunching(_ notification:Notification) {
        startedAtLogin = startedAtLogin || Self.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        NSApp.setActivationPolicy(.accessory)
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:940,height:670),
                          styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Orbit"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width:820,height:620)
        window.contentView = NSHostingView(rootView:MainView(model:model))
        window.isReleasedWhenClosed = false
        window.center()
        model.showWindow = { [weak self] in self?.showWindow() }
        gestures = GestureController(model:model)
        model.showWheel = { [weak self] file in self?.gestures.present(file,at:NSEvent.mouseLocation,dragging:false) }
        model.permissionChanged = { [weak self] in self?.gestures.start() }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        model.languageChanged = { [weak self] in self?.refreshStatus() }
        statusObservation = model.$busy.combineLatest(model.$result,model.$error)
            .receive(on:RunLoop.main).sink { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
        gestures.start()
        if !startedAtLogin { showWindow() }
        if CommandLine.arguments.contains("--demo") { model.loadDemo() }
    }

    private func refreshStatus() {
        let symbol = model.busy ? "arrow.trianglehead.2.clockwise.rotate.90" : model.error != nil ? "exclamationmark.circle" : "circle.hexagongrid"
        statusItem.button?.image = NSImage(systemSymbolName:symbol,accessibilityDescription:"Orbit")
        statusItem.button?.toolTip = model.busy ? L("Converting…","Конвертация…") : model.error ?? model.result.map { L("Saved: ","Сохранено: ") + $0.lastPathComponent } ?? "Orbit"
        let menu = NSMenu()
        menu.addItem(withTitle:L("Open Orbit","Открыть Orbit"),action:#selector(showWindow),keyEquivalent:"").target = self
        menu.addItem(withTitle:L("Choose file…","Выбрать файл…"),action:#selector(chooseFile),keyEquivalent:"").target = self
        if model.busy {
            menu.addItem(withTitle:L("Cancel conversion","Отменить конвертацию"),action:#selector(cancelConversion),keyEquivalent:"").target = self
        }
        if model.result != nil {
            menu.addItem(withTitle:L("Show last result in Finder","Показать последний результат в Finder"),action:#selector(showResult),keyEquivalent:"").target = self
        }
        if model.error != nil {
            menu.addItem(withTitle:L("Show last error…","Показать последнюю ошибку…"),action:#selector(showError),keyEquivalent:"").target = self
        }
        menu.addItem(.separator())
        let pause = NSMenuItem(title:L("Pause global gesture","Приостановить глобальный жест"),action:#selector(togglePause(_:)),keyEquivalent:"")
        pause.state = model.gesturePaused ? .on : .off
        pause.target = self; menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(withTitle:L("Quit Orbit","Завершить Orbit"),action:#selector(quit),keyEquivalent:"q").target = self
        statusItem.menu = menu

        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle:L("About Orbit","Об Orbit"),action:#selector(showWindow),keyEquivalent:"").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle:L("Quit Orbit","Завершить Orbit"),action:#selector(quit),keyEquivalent:"q").target = self
        appItem.submenu = appMenu; mainMenu.addItem(appItem)
        let editItem = NSMenuItem(); let editMenu = NSMenu(title:L("Edit","Правка"))
        for (name,action,key) in [(L("Copy","Копировать"),"copy:","c"),(L("Paste","Вставить"),"paste:","v"),(L("Select All","Выбрать всё"),"selectAll:","a")] {
            editMenu.addItem(withTitle:name,action:NSSelectorFromString(action),keyEquivalent:key)
        }
        editItem.submenu = editMenu; mainMenu.addItem(editItem); NSApp.mainMenu = mainMenu
    }

    @objc func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
    }
    @objc func chooseFile() { showWindow(); model.chooseFile() }
    @objc func showResult() { if let result = model.result { model.reveal(result) } }
    @objc func showError() { model.presentLastError() }
    @objc func cancelConversion() { model.cancel() }
    @objc func togglePause(_ sender:NSMenuItem) { model.gesturePaused.toggle(); sender.state = model.gesturePaused ? .on : .off }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard model.busy else { return .terminateNow }
        Task { await model.cancelAndWait(); sender.reply(toApplicationShouldTerminate:true) }
        return .terminateLater
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool { showWindow(); return true }
    func application(_ sender:NSApplication,openFiles filenames:[String]) {
        if let first = filenames.first { showWindow(); model.load(URL(fileURLWithPath:first)) }
        sender.reply(toOpenOrPrint:.success)
    }
}
