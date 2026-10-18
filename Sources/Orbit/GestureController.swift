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
    private var actions = false
    private var generation = UUID()
    private var timeout: Timer?
    private var resolving = false
    private var dragChangeCount = NSPasteboard(name:.drag).changeCount

    init(model:AppModel) {
        self.model=model
        panel=OrbitPanel(contentRect:NSRect(x:0,y:0,width:416,height:466), styleMask:[.borderless,.nonactivatingPanel], backing:.buffered, defer:false)
        panel.level = .popUpMenu
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient]
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        let container = NSView(frame:NSRect(x:0,y:0,width:416,height:466))
        container.addSubview(glassSurface(frame:NSRect(x:28,y:78,width:360,height:360),cornerRadius:180))
        container.addSubview(glassSurface(frame:NSRect(x:10,y:8,width:396,height:65),cornerRadius:14))
        wheel=WheelView(frame:NSRect(x:0,y:0,width:416,height:466)); container.addSubview(wheel)
        panel.contentView=container
        wheel.onSelect = { [weak self] item in self?.commit(item) }
        wheel.onDrop = { [weak self] urls,index in
            guard let self, let file=self.wheel.file, urls.first?.standardizedFileURL == file.url.standardizedFileURL,
                  self.wheel.items.indices.contains(index) else { self?.dismiss(); return }
            self.commit(self.wheel.items[index])
        }
        wheel.onCancel = { [weak self] in self?.dismiss() }
        wheel.onToggle = { [weak self] in self?.toggle() }
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
                MainActor.assumeIsolated { self?.handle(event) }
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
            let down=event.modifierFlags.contains(.shift)
            if down && !shiftDown {
                shiftDown=true
                dragging = NSEvent.pressedMouseButtons & 1 != 0
                guard !model.gesturePaused, !model.busy, model.accessibility else { return }
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder", model.finderAllowed {
                    resolve(nil,anchor:NSEvent.mouseLocation)
                } else if dragging { resolveDrag() }
            } else if !down && shiftDown {
                shiftDown=false; generation=UUID(); resolving=false
                guard panel.isVisible else { return }
                if dragging {
                    // A native drop must consume the Finder drag before starting conversion.
                    timeout=Timer.scheduledTimer(withTimeInterval:0.6,repeats:false) { [weak self] _ in
                        MainActor.assumeIsolated { self?.dismiss() }
                    }
                } else if let index=wheel.hovered, wheel.items.indices.contains(index) { commit(wheel.items[index]) }
                else { dismiss() }
            }
        }
        if event.type == .leftMouseDown { dragChangeCount=NSPasteboard(name:.drag).changeCount }
        if event.type == .leftMouseDragged && shiftDown && !panel.isVisible { dragging=true; resolveDrag() }
        guard panel.isVisible else { return }
        if [.mouseMoved,.leftMouseDragged].contains(event.type) {
            if event.type == .leftMouseDragged { dragging=true; wheel.dragging=true }
            updatePointer()
        }
        if event.type == .leftMouseUp && dragging {
            timeout=Timer.scheduledTimer(withTimeInterval:0.15,repeats:false) { [weak self] _ in MainActor.assumeIsolated { self?.dismiss() } }
        }
        if event.type == .keyDown && event.window !== panel {
            if event.keyCode == 53 { dismiss() }
            if event.keyCode == 48 { toggle() }
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
                guard generation == token, shiftDown else { return }
                present(file,at:anchor,dragging:dragging)
            } catch { model.error=error.localizedDescription }
        }
    }

    func present(_ file:FileInspection, at point:NSPoint, dragging:Bool) {
        guard !model.busy, !file.formats.isEmpty else { return }
        timeout?.invalidate(); self.dragging=dragging; wheel.dragging=dragging; actions=false
        wheel.file=file; wheel.items=file.formats.map(WheelItem.init); wheel.hovered=nil
        let screen=NSScreen.screens.first { NSMouseInRect(point,$0.frame,false) } ?? NSScreen.main!
        let area=screen.visibleFrame.insetBy(dx:8,dy:8)
        // Keep the center under the pointer unless the display edge leaves insufficient space.
        let origin=NSPoint(x:min(max(point.x-208,area.minX),area.maxX-416),
                           y:min(max(point.y-258,area.minY),area.maxY-466))
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(wheel)
    }

    private func updatePointer() {
        let screen=NSEvent.mouseLocation
        let point=panel.convertPoint(fromScreen:screen)
        wheel.track(wheel.convert(point, from:nil))
    }

    private func toggle() {
        guard let file=wheel.file else { return }
        actions.toggle(); wheel.hovered=nil
        if !actions { wheel.items=file.formats.map(WheelItem.init); return }
        var tools=[WheelItem(L("METADATA","СВЕДЕНИЯ"),"info.circle",action:"metadata")]
        if file.kind == .image {
            tools += [WheelItem(L("CROP","ОБРЕЗКА"),"crop",action:"crop"), WheelItem(L("ADD BG","ФОН"),"photo.on.rectangle",action:"background"),
                      WheelItem(L("ROTATE","ПОВОРОТ"),"rotate.right",action:"rotate"), WheelItem(L("COMPRESS","СЖАТЬ"),"arrow.down.right.and.arrow.up.left",action:"compress")]
        }
        if file.kind == .image || file.kind == .pdf { tools += [WheelItem(L("ANNOTATE","РАЗМЕТКА"),"pencil.tip",action:"preview")] }
        tools += [WheelItem(L("FORMATS","ФОРМАТЫ"),"arrow.trianglehead.2.clockwise.rotate.90",action:"formats")]
        wheel.items=tools
    }

    private func commit(_ item:WheelItem) {
        guard let file=wheel.file else { return }
        if item.action == "formats" { toggle(); return }
        dismiss()
        if let format=item.format { model.convert(format,file:file) }
        else if let action=item.action { ImageTools.perform(action,file:file,model:model) }
    }
    func dismiss() { timeout?.invalidate(); panel.orderOut(nil); wheel.hovered=nil; generation=UUID(); resolving=false }
}
