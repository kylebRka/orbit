import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    let scale=CGFloat(size)/1024
    let context=NSGraphicsContext.current!.cgContext
    context.scaleBy(x:scale,y:scale)
    let base=NSBezierPath(roundedRect:NSRect(x:24,y:24,width:976,height:976),xRadius:224,yRadius:224)
    NSGradient(colors:[NSColor(calibratedRed:0.05,green:0.4,blue:0.98,alpha:1),NSColor(calibratedRed:0.22,green:0.8,blue:1,alpha:1)])!.draw(in:base,angle:50)
    let center=NSPoint(x:512,y:512)
    for index in 0..<6 {
        let start=Double(index)*60+4, end=start+52
        let path=NSBezierPath()
        path.appendArc(withCenter:center,radius:336,startAngle:start,endAngle:end)
        path.line(to:NSPoint(x:512+172*cos(end * .pi/180),y:512+172*sin(end * .pi/180)))
        path.appendArc(withCenter:center,radius:172,startAngle:end,endAngle:start,clockwise:true)
        path.close()
        NSColor.white.withAlphaComponent(index == 5 ? 1 : 0.25+Double(index)*0.09).setFill();path.fill()
    }
    let dot=NSBezierPath(ovalIn:NSRect(x:442,y:442,width:140,height:140));NSColor.white.setFill();dot.fill()
    NSGraphicsContext.restoreGraphicsState()
    let data=rep.representation(using:.png,properties:[:])!
    if size == 1024 { try data.write(to:URL(fileURLWithPath:directory+"/icon_512x512@2x.png")) }
    else if size == 64 { try data.write(to:URL(fileURLWithPath:directory+"/icon_32x32@2x.png")) }
    else {
        try data.write(to:URL(fileURLWithPath:directory+"/icon_\(size)x\(size).png"))
        if size >= 32 { try data.write(to:URL(fileURLWithPath:directory+"/icon_\(size/2)x\(size/2)@2x.png")) }
    }
}
