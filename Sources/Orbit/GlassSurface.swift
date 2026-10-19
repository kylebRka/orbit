import AppKit

@MainActor
func glassSurface(frame:NSRect, cornerRadius:CGFloat) -> NSView {
    if #available(macOS 26.0, *) {
        let glass=NSGlassEffectView(frame:frame)
        glass.style = .regular
        glass.cornerRadius=cornerRadius
        glass.contentView=NSView(frame:NSRect(origin:.zero,size:frame.size))
        return glass
    }
    let glass=NSVisualEffectView(frame:frame)
    glass.material = .hudWindow
    glass.blendingMode = .behindWindow
    glass.state = .active
    glass.wantsLayer=true
    glass.layer?.cornerRadius=cornerRadius
    return glass
}
