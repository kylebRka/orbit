import AppKit
import QuickLookUI
import OrbitCore

enum WheelPage: Int, CaseIterable, Identifiable {
    case formats, tools, actions
    var id:Int { rawValue }
    var key:String { switch self { case .formats: "⇧"; case .tools: "⌘"; case .actions: "⌃" } }
    var title:String { switch self { case .formats: L("Convert","Форматы"); case .tools: L("Tools","Инструменты"); case .actions: L("Actions","Действия") } }
    var next:Self { Self(rawValue:(rawValue+1)%Self.allCases.count)! }
}

enum WheelCatalog {
    static func items(for file:FileInspection, page:WheelPage) -> [WheelItem] {
        switch page {
        case .formats: return file.formats.map(WheelItem.init)
        case .tools:
            var tools=[WheelItem(L("INFO","СВЕДЕНИЯ"),"info.circle",action:"metadata")]
            if file.kind == .image {
                tools += [WheelItem(L("CROP","ОБРЕЗКА"),"crop",action:"crop"),WheelItem(L("ADD BG","ФОН"),"photo.on.rectangle",action:"background"),
                          WheelItem(L("ROTATE","ПОВОРОТ"),"rotate.right",action:"rotate"),WheelItem(L("COMPRESS","СЖАТЬ"),"arrow.down.right.and.arrow.up.left",action:"compress")]
            }
            if file.kind == .video || file.kind == .audio {
                tools.insert(WheelItem(L("TRIM","ОБРЕЗАТЬ"),"timeline.selection",action:"trim"),at:0)
            }
            if file.kind == .image || file.kind == .pdf { tools += [WheelItem(L("ANNOTATE","РАЗМЕТКА"),"pencil.tip",action:"preview")] }
            return tools
        case .actions:
            return [WheelItem("AirDrop","airplay.audio",action:"airdrop"),WheelItem(L("FLOAT","ПОВЕРХ ОКОН"),"pin",action:"float"),
                    WheelItem(L("COPY","КОПИРОВАТЬ"),"document.on.document",action:"copy"),WheelItem(L("MOVE","ПЕРЕМЕСТИТЬ"),"folder.badge.arrow.forward",action:"move"),
                    WheelItem(L("COPY PATH","ПУТЬ"),"link",action:"copyPath"),WheelItem("Terminal","terminal",action:"terminal")]
        }
    }
}

@MainActor
enum FileActions {
    static func perform(_ action:String, file:FileInspection, model:AppModel, background:Bool = false) {
        guard !model.busy else { return }
        do {
            guard file.url.isFileURL, FileManager.default.fileExists(atPath:file.url.path) else { throw OrbitError.message(L("The file is no longer available.","Файл больше недоступен.")) }
            switch action {
            case "trim":
                ImageTools.show(MediaTrimView(file:file,model:model),title:file.kind == .video ? L("Trim video","Обрезать видео") : L("Trim audio","Обрезать аудио"),model:model)
            case "copy":
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.writeObjects([file.url as NSURL]) else { throw OrbitError.message(L("Cannot copy this file.","Не удалось скопировать файл.")) }
            case "copyPath":
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(file.url.path,forType:.string)
            case "airdrop":
                guard let service=NSSharingService(named:.sendViaAirDrop), service.canPerform(withItems:[file.url]) else { throw OrbitError.message(L("AirDrop is unavailable on this Mac.","AirDrop недоступен на этом Mac.")) }
                NSApp.activate(ignoringOtherApps:true); service.perform(withItems:[file.url])
            case "float":
                let window=NSWindow(contentRect:NSRect(x:0,y:0,width:620,height:460),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
                let view=QLPreviewView(frame:window.contentLayoutRect,style:.normal)!
                view.previewItem=file.url as NSURL
                window.contentView=view; window.level = .floating; window.title=file.url.lastPathComponent
                window.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary]
                window.isReleasedWhenClosed=false; model.editor?.close(); model.editor=window
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
            case "move":
                NSApp.activate(ignoringOtherApps:true)
                let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.canCreateDirectories=true
                panel.prompt=L("Move here","Переместить сюда"); panel.message=L("Choose a destination for ","Выберите папку для ")+file.url.lastPathComponent
                guard panel.runModal() == .OK, let directory=panel.url else { return }
                let target=try move(file.url,to:directory)
                model.file=FileInspection(url:target,kind:file.kind,hasAudio:file.hasAudio,detail:file.detail,formats:file.formats,duration:file.duration)
                model.result=nil
            case "terminal":
                let configuration=NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open([file.url.deletingLastPathComponent()],withApplicationAt:URL(fileURLWithPath:"/System/Applications/Utilities/Terminal.app"),configuration:configuration) { _,error in
                    if let error { Task { @MainActor in model.reportError(error,present:!background) } }
                }
            default: ImageTools.perform(action,file:file,model:model,background:background)
            }
        } catch { model.reportError(error,present:!background) }
    }

    static func move(_ source:URL,to directory:URL) throws -> URL {
        guard source.isFileURL, directory.isFileURL,
              try directory.resourceValues(forKeys:[.isDirectoryKey]).isDirectory == true else { throw OrbitError.message(L("Choose a local folder.","Выберите локальную папку.")) }
        let target=directory.appendingPathComponent(source.lastPathComponent)
        if target.standardizedFileURL == source.standardizedFileURL { return source }
        // FileManager refuses a destination that already exists, preserving both files.
        try FileManager.default.moveItem(at:source,to:target)
        return target
    }
}
