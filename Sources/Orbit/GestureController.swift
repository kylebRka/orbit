import AppKit
import OrbitCore

final class OrbitPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GestureController {
    private let model: AppModel
    private let panel: OrbitPanel
    private let wheel: WheelView
    private var global: Any?
    private var local: Any?
    private var permissionObserver: NSObjectProtocol?
    private var shiftDown = false
    private var dragging = false
    private var page=WheelPage.formats
    private var heldModifiers:NSEvent.ModifierFlags=[]
    private var selectionGesture=false
    private var background = false
    private var generation = UUID()
    private var timeout: Timer?
    private var resolving = false
    private var dragChangeCount = NSPasteboard(name:.drag).changeCount

    init(model:AppModel) {
        self.model=model
        panel=OrbitPanel(contentRect:NSRect(x:0,y:0,width:416,height:520), styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
        panel.level = .popUpMenu
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let container = NSView(frame:NSRect(x:0,y:0,width:416,height:520))
        container.addSubview(glassSurface(frame:NSRect(x:28,y:82,width:360,height:360),cornerRadius:180))
        container.addSubview(glassSurface(frame:NSRect(x:10,y:8,width:396,height:65),cornerRadius:14))
        container.addSubview(glassSurface(frame:NSRect(x:10,y:472,width:396,height:40),cornerRadius:13))
        wheel=WheelView(frame:NSRect(x:0,y:0,width:416,height:520)); container.addSubview(wheel)
        panel.contentView=container
        wheel.onSelect = { [weak self] item in self?.commit(item) }
        wheel.onDrop = { [weak self] urls,index in
            guard let self, let file=self.wheel.file, urls.first?.standardizedFileURL == file.url.standardizedFileURL,
                  self.wheel.items.indices.contains(index) else { self?.dismiss(); return }
            self.commit(self.wheel.items[index])
        }
        wheel.onCancel = { [weak self] in self?.dismiss() }
        wheel.onToggle = { [weak self] in guard let self else { return }; self.changePage(self.page.next) }
        wheel.onPage = { [weak self] page in self?.changePage(page) }
        permissionObserver=NotificationCenter.default.addObserver(forName:NSApplication.didBecomeActiveNotification, object:nil, queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshPermissions() }
        }
    }

    func start() {
        if !model.accessibility, let global {
            NSEvent.removeMonitor(global); self.global=nil
        }
        if model.accessibility && global == nil {
            global=NSEvent.addGlobalMonitorForEvents(matching:[.flagsChanged,.mouseMoved,.leftMouseDown,.leftMouseDragged,.leftMouseUp,.keyDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handle(event)
                    if self.panel.isVisible && event.type == .keyDown && [48,53].contains(event.keyCode) { self.wheel.keyDown(with:event) }
                }
            }
        }
        if local == nil {
            local=NSEvent.addLocalMonitorForEvents(matching:[.flagsChanged,.mouseMoved,.leftMouseDown,.leftMouseDragged,.leftMouseUp,.keyDown]) { [weak self] event in
                var consume = false
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.handle(event)
                    if self.panel.isVisible && event.type == .keyDown && [48,53,123,124,125,126,36,76].contains(event.keyCode) {
                        self.wheel.keyDown(with:event); consume = true
                    }
                }
                return consume ? nil : event
            }
        }
    }

    private func handle(_ event:NSEvent) {
        if event.type == .flagsChanged {
            let flags=event.modifierFlags.intersection([.shift,.command,.control])
            let pressed=flags.subtracting(heldModifiers)
            let releasedShift=heldModifiers.contains(.shift) && !flags.contains(.shift)
            heldModifiers=flags; shiftDown=flags.contains(.shift)
            if panel.isVisible {
                if pressed.contains(.control) { changePage(.actions) }
                else if pressed.contains(.command) { changePage(.tools) }
                else if pressed.contains(.shift) { changePage(.formats) }
                if releasedShift && selectionGesture && !dragging {
                    if let index=wheel.hovered, wheel.items.indices.contains(index) { commit(wheel.items[index]) }
                    else { dismiss() }
                }
            } else {
                if releasedShift && !dragging { generation=UUID(); resolving=false; selectionGesture=false; dragging=false }
                let isDrag=NSEvent.pressedMouseButtons & 1 != 0
                let requested:WheelPage?=pressed.contains(.control) ? .actions : pressed.contains(.command) ? .tools : pressed.contains(.shift) ? .formats : nil
                if let requested, (isDrag || pressed.contains(.shift)), !model.gesturePaused, !model.busy, model.accessibility {
                    dragging=isDrag; selectionGesture = !isDrag; page=requested
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", model.finderAllowed {
                        resolve(nil,anchor:NSEvent.mouseLocation)
                    } else if isDrag { resolveDrag() }
                }
            }
        }
        if event.type == .leftMouseDown { dragChangeCount=NSPasteboard(name:.drag).changeCount }
        if event.type == .leftMouseDragged && !heldModifiers.isEmpty && !panel.isVisible {
            dragging=true; selectionGesture=false
            page=heldModifiers.contains(.control) ? .actions : heldModifiers.contains(.command) ? .tools : .formats
            resolveDrag()
        }
        if event.type == .leftMouseUp && !panel.isVisible { if resolving { dismiss() }; dragging=false }
        guard panel.isVisible else { return }
        if [.mouseMoved,.leftMouseDragged].contains(event.type) {
            if event.type == .leftMouseDragged { dragging=true; wheel.dragging=true }
            updatePointer()
        }
        if event.type == .leftMouseUp && dragging {
            timeout=Timer.scheduledTimer(withTimeInterval:0.15,repeats:false) { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } }
        }
    }

    private func resolveDrag() {
        guard !model.gesturePaused, !model.busy, model.accessibility, !resolving else { return }
        let pasteboard=NSPasteboard(name:.drag)
        guard pasteboard.changeCount != dragChangeCount else { return }
        let urls=pasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
        guard urls.count == 1 else { return }
        resolve(urls,anchor:NSEvent.mouseLocation)
    }

    private func resolve(_ urls:[URL]?,anchor:NSPoint) {
        guard !resolving else { return }
        resolving=true
        let token=UUID(); generation=token
        Task {
            defer { if generation == token { resolving=false } }
            do {
                let selection:[URL]
                if let urls { selection=urls } else { selection=try await FinderSelection.read() }
                guard selection.count == 1, let url=selection.first else { return }
                let file=try await Task.detached(priority:.userInitiated) { try await ConversionEngine.inspect(url) }.value
                guard generation == token, dragging || shiftDown else { return }
                present(file,at:anchor,dragging:dragging,initialPage:page,preserveGesture:true)
            } catch { model.reportError(error,present:false) }
        }
    }

    func present(_ file:FileInspection, at point:NSPoint, dragging:Bool, initialPage:WheelPage = .formats, preserveGesture:Bool = false) {
        guard !model.busy else { return }
        timeout?.invalidate(); self.dragging=dragging; wheel.dragging=dragging
        if !preserveGesture { selectionGesture=false }
        page=initialPage == .formats && file.formats.isEmpty ? .tools : initialPage; wheel.page=page
        background = NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier
        let screen=NSScreen.screens.first { NSMouseInRect(point,$0.frame,false) } ?? NSScreen.main!
        let area=screen.visibleFrame.insetBy(dx:8,dy:8)
        // Keep the center under the pointer unless the display edge leaves insufficient space.
        let origin=NSPoint(x:min(max(point.x-208,area.minX),area.maxX-416),
                           y:min(max(point.y-262,area.minY),area.maxY-520))
        panel.setFrameOrigin(origin)
        wheel.file=file; wheel.items=WheelCatalog.items(for:file,page:page); wheel.hovered=nil
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wheel)
    }

    private func updatePointer() {
        let screen=NSEvent.mouseLocation
        let point=panel.convertPoint(fromScreen:screen)
        wheel.track(wheel.convert(point, from:nil))
    }

    private func changePage(_ page:WheelPage) {
        guard let file=wheel.file else { return }
        self.page=page; wheel.page=page; wheel.hovered=nil
        wheel.items=WheelCatalog.items(for:file,page:page)
    }

    private func commit(_ item:WheelItem) {
        guard let file=wheel.file else { return }
        dismiss()
        if let format=item.format { model.convert(format,file:file,background:background) }
        else if let action=item.action { FileActions.perform(action,file:file,model:model,background:background) }
    }
    func dismiss() { timeout?.invalidate(); panel.orderOut(nil); wheel.hovered=nil; generation=UUID(); resolving=false; selectionGesture=false; dragging=false }
}
