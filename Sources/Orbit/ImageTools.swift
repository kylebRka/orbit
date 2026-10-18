import AppKit
import SwiftUI
import ImageIO
import OrbitCore

@MainActor
enum ImageTools {
    static func perform(_ action:String, file:FileInspection, model:AppModel, background:Bool = false) {
        do {
            if action == "metadata" {
                var lines=[file.url.lastPathComponent,file.detail,"Type: \(file.kind.rawValue)"]
                if let source=CGImageSourceCreateWithURL(file.url as CFURL,nil), let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) {
                    lines.append(String(describing:properties))
                }
                let view=VStack(alignment:.leading,spacing:15) {
                    Text(L("File information","Сведения о файле")).font(.title2.weight(.semibold))
                    ScrollView { Text(lines.joined(separator:"\n\n")).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
                }.padding(24).frame(width:540,height:460)
                show(view,title:L("Metadata","Метаданные"),model:model); return
            }
            if action == "preview" {
                let configuration=NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([file.url],withApplicationAt:URL(fileURLWithPath:"/System/Applications/Preview.app"),configuration:configuration) { _,error in
                    if let error { Task { @MainActor in model.reportError(error,present:!background) } }
                }; return
            }
            let image=try ConversionEngine.loadImage(file.url)
            if action == "rotate" {
                guard let context=CGContext(data:nil,width:image.height,height:image.width,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OrbitError.message("Cannot rotate image.") }
                context.translateBy(x:0,y:CGFloat(image.width)); context.rotate(by:-.pi/2)
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
                guard let rotated=context.makeImage() else { throw OrbitError.message("Cannot rotate image.") }
                try save(rotated,file:file,format:.png,suffix:"-rotated",model:model); return
            }
            if action == "compress" { try save(image,file:file,format:.jpg,suffix:"-compressed",model:model,quality:0.65); return }
            show(ImageEditor(image:image,file:file,background:action == "background",model:model),
                 title:action == "background" ? L("Add background","Добавить фон") : L("Crop image","Обрезать изображение"),model:model)
        } catch { model.reportError(error,present:!background) }
    }

    static func save(_ image:CGImage,file:FileInspection,format:OutputFormat,suffix:String,model:AppModel,quality:Double=0.9) throws {
        let temp=file.url.deletingLastPathComponent().appendingPathComponent(".orbit-\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at:temp) }
        try ConversionEngine.writeImage(image,to:temp,format:format,quality:quality)
        if suffix == "-compressed" {
            let oldSize=try file.url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            let newSize=try temp.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
            guard newSize < oldSize else { throw OrbitError.message(L("The original is already smaller than this JPEG. No larger copy was saved.","Оригинал уже меньше этого JPEG. Более крупная копия не сохранена.")) }
        }
        let output=try OutputFiles.publish(temp,beside:file.url,extension:format.rawValue,suffix:suffix)
        model.editor?.close(); model.completed(output)
    }

    static func show<V:View>(_ view:V,title:String,model:AppModel) {
        model.editor?.close()
        let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:720),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        window.title=title; window.isReleasedWhenClosed=false
        window.contentView=NSHostingView(rootView:view)
        NSApp.setActivationPolicy(.regular)
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
        model.editor=window
    }
}

struct ImageEditor:View {
    let image:CGImage
    let file:FileInspection
    let background:Bool
    @ObservedObject var model:AppModel
    @State private var editorError:String?
    @State private var padding=0.12
    @State private var corners=0.04
    @State private var shadow=0.04
    @State private var color=Color.accentColor
    @State private var showLogo=true
    @State private var corner="br"
    @State private var customLogo:CGImage?
    @State private var cropWidth=0.8
    @State private var cropHeight=0.8
    @State private var cropX=0.1
    @State private var cropY=0.1
    @State private var dragOrigin:CGPoint?

    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(background ? L("Make room for your image.","Добавьте пространства.") : L("Keep the part that matters.","Оставьте самое важное.")).font(.title2.weight(.semibold))
                    Text(file.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }; Spacer()
                Image(systemName:background ? "photo.on.rectangle.angled" : "crop").font(.title).foregroundStyle(Color.accentColor)
            }
            ZStack {
                RoundedRectangle(cornerRadius:14).fill(Color(nsColor:.underPageBackgroundColor))
                if background, let result=try? renderBackground(preview:true) {
                    Image(decorative:result,scale:1).resizable().scaledToFit().padding(18)
                } else {
                    GeometryReader { proxy in
                        let fit=min(proxy.size.width / CGFloat(image.width),proxy.size.height / CGFloat(image.height))
                        let size=CGSize(width:CGFloat(image.width)*fit,height:CGFloat(image.height)*fit)
                        ZStack(alignment:.topLeading) {
                            Image(decorative:image,scale:1).resizable().frame(width:size.width,height:size.height).opacity(0.45)
                            Image(decorative:image,scale:1).resizable().frame(width:size.width,height:size.height)
                                .mask(Rectangle().frame(width:size.width*cropWidth,height:size.height*cropHeight).offset(x:size.width*cropX,y:size.height*cropY).frame(width:size.width,height:size.height,alignment:.topLeading))
                            Rectangle().stroke(Color.accentColor,lineWidth:2).background(.white.opacity(0.03))
                                .frame(width:size.width*cropWidth,height:size.height*cropHeight).offset(x:size.width*cropX,y:size.height*cropY)
                                .gesture(DragGesture().onChanged { gesture in
                                    if dragOrigin == nil { dragOrigin=CGPoint(x:cropX,y:cropY) }
                                    cropX=min(max(0,dragOrigin!.x+gesture.translation.width/size.width),1-cropWidth)
                                    cropY=min(max(0,dragOrigin!.y+gesture.translation.height/size.height),1-cropHeight)
                                }.onEnded { _ in dragOrigin=nil })
                        }.frame(width:proxy.size.width,height:proxy.size.height)
                    }.padding(20)
                }
            }.frame(height:330)
            if background {
                HStack { Text(L("Background","Фон")); Spacer(); ColorPicker("",selection:$color,supportsOpacity:false).labelsHidden() }
                slider(L("Padding","Отступ"),value:$padding,range:0.03...0.4)
                slider(L("Corners","Скругление"),value:$corners,range:0...0.15)
                slider(L("Shadow","Тень"),value:$shadow,range:0...0.12)
                Divider()
                HStack {
                    Toggle(L("Add logo","Добавить логотип"),isOn:$showLogo)
                    Spacer()
                    Button(customLogo == nil ? L("Use your logo…","Свой логотип…") : L("Replace logo…","Заменить логотип…")) { chooseLogo() }.disabled(!showLogo)
                    if customLogo != nil { Button(L("Orbit logo","Логотип Orbit")) { customLogo=nil }.disabled(!showLogo) }
                }
                Picker(L("Position","Положение"),selection:$corner) {
                    Text("↖").tag("tl"); Text("↗").tag("tr"); Text("↙").tag("bl"); Text("↘").tag("br")
                }.pickerStyle(.segmented).disabled(!showLogo).accessibilityLabel(L("Logo corner: top left, top right, bottom left, bottom right","Угол логотипа: верхний левый, верхний правый, нижний левый, нижний правый"))
            } else {
                slider(L("Width","Ширина"),value:$cropWidth,range:0.05...1)
                slider(L("Height","Высота"),value:$cropHeight,range:0.05...1)
                HStack {
                    Text(L("Drag the selection to move it.","Перемещайте рамку мышью.")).font(.caption).foregroundStyle(.secondary)
                    Spacer(); Text("\(Int(Double(image.width)*cropWidth)) × \(Int(Double(image.height)*cropHeight))").font(.caption.monospacedDigit())
                }
                Button(L("Reset","Сбросить")) { cropX=0; cropY=0; cropWidth=1; cropHeight=1 }
            }
            Spacer(minLength:0)
            HStack {
                Text(L("Saves a new PNG. Original stays intact.","Сохранится новый PNG. Оригинал останется.")).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel","Отмена")) { model.editor?.close() }.keyboardShortcut(.cancelAction)
                Button(L("Save image","Сохранить")) { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width:620,height:background ? 760 : 620)
            .environment(\.locale,model.language.locale)
            .alert(L("Cannot save image","Не удалось сохранить изображение"),isPresented:Binding(get:{ editorError != nil },set:{ if !$0 { editorError=nil } })) {
                Button("OK") { editorError=nil }
            } message: { Text(editorError ?? "") }
            .onChange(of:cropWidth) { _,value in cropX=min(cropX,1-value) }
            .onChange(of:cropHeight) { _,value in cropY=min(cropY,1-value) }
    }

    func slider(_ label:String,value:Binding<Double>,range:ClosedRange<Double>) -> some View {
        HStack { Text(label).font(.system(size:12)).frame(width:90,alignment:.leading); Slider(value:value,in:range); Text("\(Int(value.wrappedValue*100))%").font(.caption.monospacedDigit()).frame(width:38,alignment:.trailing) }
    }

    func chooseLogo() {
        let panel=NSOpenPanel(); panel.allowedContentTypes=[.image]; panel.allowsMultipleSelection=false
        if panel.runModal() == .OK, let url=panel.url {
            do { customLogo=try ConversionEngine.loadImage(url) } catch { editorError=error.localizedDescription }
        }
    }

    func renderBackground(preview:Bool) throws -> CGImage {
        let margin=CGFloat(max(image.width,image.height))*padding
        let total=CGSize(width:CGFloat(image.width)+margin*2,height:CGFloat(image.height)+margin*2)
        let scale=min(1,(preview ? 1100.0 : 8192.0)/max(total.width,total.height))
        let width=Int(total.width*scale),height=Int(total.height*scale)
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw OrbitError.message("Cannot create background.") }
        context.scaleBy(x:scale,y:scale)
        let base=NSColor(color).usingColorSpace(.deviceRGB) ?? .systemBlue
        let light=base.blended(withFraction:0.38,of:.white) ?? base
        let gradient=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[base.cgColor,light.cgColor] as CFArray,locations:[0,1])!
        context.drawLinearGradient(gradient,start:.zero,end:CGPoint(x:total.width,y:total.height),options:[])
        let rect=CGRect(x:margin,y:margin,width:CGFloat(image.width),height:CGFloat(image.height))
        let radius=CGFloat(min(image.width,image.height))*corners
        let path=CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil)
        context.saveGState()
        context.setShadow(offset:CGSize(width:0,height:-margin*0.12),blur:CGFloat(max(image.width,image.height))*shadow,color:CGColor(gray:0,alpha:0.28))
        context.addPath(path); context.setFillColor(CGColor(gray:1,alpha:1)); context.fillPath()
        context.restoreGState()
        context.saveGState(); context.addPath(path); context.clip(); context.draw(image,in:rect); context.restoreGState()
        if showLogo {
            let logo=customLogo ?? defaultLogo()
            if let logo {
                let maxSide=min(total.width,total.height)*0.105
                let factor=maxSide/CGFloat(max(logo.width,logo.height))
                let size=CGSize(width:CGFloat(logo.width)*factor,height:CGFloat(logo.height)*factor)
                let inset=min(margin*0.3,maxSide*0.3)
                let x=corner.hasSuffix("r") ? total.width-size.width-inset : inset
                let y=corner.hasPrefix("t") ? total.height-size.height-inset : inset
                context.saveGState(); context.setShadow(offset:.zero,blur:4,color:CGColor(gray:0,alpha:0.15))
                context.draw(logo,in:CGRect(origin:CGPoint(x:x,y:y),size:size)); context.restoreGState()
            }
        }
        guard let output=context.makeImage() else { throw OrbitError.message("Cannot render background.") }
        return output
    }

    func defaultLogo() -> CGImage? {
        if let url=Bundle.main.url(forResource:"AppIcon",withExtension:"png"), let image=try? ConversionEngine.loadImage(url) {
            return image
        }
        return NSImage(systemSymbolName:"circle.hexagongrid.fill",accessibilityDescription:nil)?.cgImage(forProposedRect:nil,context:nil,hints:nil)
    }

    func save() {
        do {
            let output:CGImage
            if background { output=try renderBackground(preview:false) }
            else {
                let rect=CGRect(x:CGFloat(image.width)*cropX,y:CGFloat(image.height)*cropY,width:CGFloat(image.width)*cropWidth,height:CGFloat(image.height)*cropHeight).integral
                guard let cropped=image.cropping(to:rect) else { throw OrbitError.message("Invalid crop area.") }; output=cropped
            }
            try ImageTools.save(output,file:file,format:.png,suffix:background ? "-background" : "-cropped",model:model)
        } catch { editorError=error.localizedDescription }
    }
}
