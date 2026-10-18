import AppKit
import SwiftUI
import OrbitCore

struct WheelItem {
    let title: String
    let symbol: String
    let format: OutputFormat?
    let action: String?
    init(_ format: OutputFormat) { self.title = format.title; self.symbol = format.symbol; self.format = format; self.action = nil }
    init(_ title: String, _ symbol: String, action: String) { self.title = title; self.symbol = symbol; self.action = action; self.format = nil }
}

@MainActor
final class WheelAccessibilityItem:NSAccessibilityElement {
    var press:(() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}

@MainActor
final class WheelView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var items: [WheelItem] = [] { didSet { needsDisplay = true; updateAccessibilityItems() } }
    var hovered: Int? { didSet { needsDisplay = true } }
    var file: FileInspection? { didSet { needsDisplay = true } }
    var demo = false
    var dragging = false { didSet { needsDisplay=true } }
    var onSelect: ((WheelItem) -> Void)?
    var onDrop: (([URL], Int) -> Void)?
    var onCancel: (() -> Void)?
    var onToggle: (() -> Void)?
    private var tracking: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame:frame)
        registerForDraggedTypes([.fileURL])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("Conversion wheel. Use arrow keys, Return to choose, Tab for tools, Escape to cancel.", "Меню конвертации. Стрелки — выбор, Enter — запуск, Tab — инструменты, Escape — отмена."))
        NotificationCenter.default.addObserver(self, selector:#selector(colorsChanged), name:NSColor.systemColorsDidChangeNotification, object:nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func colorsChanged() { needsDisplay = true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateAccessibilityItems() }
    private func updateAccessibilityItems() {
        guard !demo else { return }
        var elements:[WheelAccessibilityItem] = []
        for (index,item) in items.enumerated() {
            let element=WheelAccessibilityItem()
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(item.title)
            element.setAccessibilityParent(self)
            let angle=(-90+Double(index)*360/Double(items.count)) * .pi/180
            let rect=NSRect(x:208+118*cos(angle)-32,y:208+118*sin(angle)-24,width:64,height:48)
            element.setAccessibilityFrame(window?.convertToScreen(convert(rect,to:nil)) ?? .zero)
            element.press = { [weak self] in self?.onSelect?(item) }
            elements.append(element)
        }
        let toggle=WheelAccessibilityItem()
        toggle.setAccessibilityRole(.button)
        toggle.setAccessibilityEnabled(true)
        toggle.setAccessibilityLabel(L("Switch formats and tools","Переключить форматы и инструменты"))
        toggle.setAccessibilityParent(self)
        toggle.setAccessibilityFrame(window?.convertToScreen(convert(NSRect(x:151,y:151,width:114,height:114),to:nil)) ?? .zero)
        toggle.press = { [weak self] in self?.onToggle?() }
        elements.append(toggle)
        setAccessibilityChildren(elements)
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect:bounds, options:[.mouseMoved, .activeAlways, .inVisibleRect], owner:self)
        addTrackingArea(tracking!); super.updateTrackingAreas()
    }
    func track(_ point: NSPoint) {
        let selected = RadialGeometry.sector(x:point.x - 208, y:point.y - 208, count:items.count)
        if hovered != selected { hovered = selected }
    }
    override func mouseMoved(with event: NSEvent) { track(convert(event.locationInWindow, from:nil)) }
    override func mouseDown(with event: NSEvent) {
        track(convert(event.locationInWindow, from:nil))
        if let hovered, items.indices.contains(hovered) { onSelect?(items[hovered]) }
        else { onCancel?() }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 48: onToggle?()
        case 123, 126: hovered = ((hovered ?? 0) - 1 + max(1,items.count)) % max(1,items.count)
        case 124, 125: hovered = ((hovered ?? -1) + 1) % max(1,items.count)
        case 36, 76: if let hovered, items.indices.contains(hovered) { onSelect?(items[hovered]) }
        default: super.keyDown(with:event)
        }
    }
    func acceptsFiles(_ urls:[URL]) -> Bool {
        urls.count == 1 && urls.first?.standardizedFileURL == file?.url.standardizedFileURL
    }
    private func draggedFiles(_ sender:NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL] ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsFiles(draggedFiles(sender)) else { hovered=nil; return [] }
        track(convert(sender.draggingLocation, from:nil)); return hovered == nil ? [] : .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovered = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { hovered != nil && acceptsFiles(draggedFiles(sender)) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        track(convert(sender.draggingLocation, from:nil))
        let files = draggedFiles(sender)
        guard let hovered, acceptsFiles(files) else { onCancel?(); return false }
        onDrop?(files, hovered); return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let center = NSPoint(x:208,y:208)
        let outer = NSBezierPath(ovalIn:NSRect(x:28,y:28,width:360,height:360))
        NSColor.windowBackgroundColor.withAlphaComponent(0.04).setFill(); outer.fill()
        NSColor.white.withAlphaComponent(0.36).setStroke(); outer.lineWidth = 1; outer.stroke()
        guard !items.isEmpty else { return }
        let step = 360 / Double(items.count)
        for (index, item) in items.enumerated() {
            let start = -90 + Double(index) * step - step/2 + 1.7
            let end = start + step - 3.4
            let shape = NSBezierPath()
            func point(_ radius:Double, _ degrees:Double) -> NSPoint {
                NSPoint(x:center.x+radius*cos(degrees * .pi/180),y:center.y+radius*sin(degrees * .pi/180))
            }
            shape.move(to:point(174,start+3))
            shape.appendArc(withCenter:center, radius:174, startAngle:start+3, endAngle:end-3, clockwise:false)
            shape.curve(to:point(165,end),controlPoint1:point(174,end),controlPoint2:point(174,end))
            shape.line(to:point(74,end))
            shape.curve(to:point(65,end-7),controlPoint1:point(65,end),controlPoint2:point(65,end))
            shape.appendArc(withCenter:center, radius:65, startAngle:end-7, endAngle:start+7, clockwise:true)
            shape.curve(to:point(74,start),controlPoint1:point(65,start),controlPoint2:point(65,start))
            shape.line(to:point(165,start))
            shape.curve(to:point(174,start+3),controlPoint1:point(174,start),controlPoint2:point(174,start))
            shape.close()
            let selected = hovered == index
            let opaque = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            (selected ? NSColor.controlAccentColor.withAlphaComponent(opaque ? 1 : 0.67) : NSColor.controlBackgroundColor.withAlphaComponent(opaque ? 0.95 : 0.12)).setFill()
            shape.fill()
            if !selected && !opaque { NSColor.labelColor.withAlphaComponent(0.025).setFill(); shape.fill() }
            NSGradient(starting:NSColor.white.withAlphaComponent(selected ? 0.23 : 0.2),ending:NSColor.white.withAlphaComponent(0.015))?.draw(in:shape,angle:-45)
            NSColor.separatorColor.withAlphaComponent(0.16).setStroke(); shape.lineWidth = 1.5; shape.stroke()
            NSColor.white.withAlphaComponent(0.4).setStroke(); shape.lineWidth = 0.6; shape.stroke()
            let angle = (-90 + Double(index)*step) * .pi/180
            let point = NSPoint(x:center.x+118*cos(angle),y:center.y+118*sin(angle))
            let color = selected ? NSColor.white : NSColor.labelColor
            if let icon = NSImage(systemSymbolName:item.symbol, accessibilityDescription:nil)?.withSymbolConfiguration(.init(pointSize:17, weight:.medium)) {
                let tinted = NSImage(size:NSSize(width:24,height:24))
                tinted.lockFocus(); color.set(); let rect=NSRect(x:0,y:0,width:24,height:24)
                icon.draw(in:rect); rect.fill(using:.sourceAtop); tinted.unlockFocus()
                tinted.draw(in:NSRect(x:point.x-12,y:point.y-22,width:24,height:24))
            }
            let paragraph=NSMutableParagraphStyle(); paragraph.alignment = .center
            let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:10,weight:.semibold), .foregroundColor:color, .paragraphStyle:paragraph]
            (item.title as NSString).draw(in:NSRect(x:point.x-44,y:point.y+10,width:88,height:28),withAttributes:attrs)
        }
        let middle = NSBezierPath(ovalIn:NSRect(x:151,y:151,width:114,height:114))
        NSColor.controlBackgroundColor.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 0.95 : 0.22).setFill(); middle.fill()
        if let file {
            let icon = NSWorkspace.shared.icon(forFile:file.url.path)
            icon.draw(in:NSRect(x:186,y:165,width:44,height:44))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
        let title = hovered.flatMap { items.indices.contains($0) ? items[$0].title : nil } ?? "ORBIT"
        (title as NSString).draw(in:NSRect(x:156,y:217,width:104,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:11,weight:.bold), .foregroundColor:NSColor.labelColor, .paragraphStyle:paragraph])
        if !demo {
            let filename = file?.url.lastPathComponent ?? ""
            (filename as NSString).draw(in:NSRect(x:28,y:401,width:360,height:20),withAttributes:[.font:NSFont.systemFont(ofSize:12,weight:.medium), .foregroundColor:NSColor.labelColor,.paragraphStyle:paragraph])
            let hint = dragging ? L("Drop onto a format · Tab tools · Esc cancel", "Бросьте файл в сектор · Tab — инструменты · Esc — отмена") : L("Release Shift to convert · Tab tools · Esc cancel", "Отпустите Shift · Tab — инструменты · Esc — отмена")
            (hint as NSString).draw(in:NSRect(x:4,y:426,width:408,height:30),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:NSColor.secondaryLabelColor,.paragraphStyle:paragraph])
        }
    }
}

struct WheelPreview: NSViewRepresentable {
    let file: FileInspection?
    func makeNSView(context:Context) -> WheelView { let view=WheelView(frame:NSRect(x:0,y:0,width:416,height:416)); view.demo=true; return view }
    func updateNSView(_ view:WheelView, context:Context) {
        view.file=file
        view.items = (file?.formats ?? [.png,.jpg,.heic,.tiff,.bmp,.pdf]).map(WheelItem.init)
        view.hovered = 1
    }
}
