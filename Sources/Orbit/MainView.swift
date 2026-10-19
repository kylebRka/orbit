import SwiftUI
import AppKit
import OrbitCore
import ServiceManagement

struct MainView: View {
    @ObservedObject var model:AppModel
    @State private var dropTarget=false
    @State private var page=WheelPage.formats
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body:some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:8) {
                HStack(spacing:10) {
                    Image(systemName:"circle.hexagongrid.fill").font(.system(size:27)).foregroundStyle(Color.accentColor)
                    Text("Orbit").font(.system(size:23,weight:.semibold,design:.rounded))
                }.padding(.bottom,30).padding(.top,42)
                nav("convert",L("Convert","Конвертация"),"arrow.trianglehead.2.clockwise.rotate.90")
                nav("recent",L("Recent files","Недавние файлы"),"clock")
                nav("settings",L("Settings","Настройки"),"slider.horizontal.3")
                Spacer()
                VStack(alignment:.leading,spacing:9) {
                    HStack(spacing:6) { Circle().fill(.green).frame(width:6,height:6); Text(L("ON YOUR MAC","НА ВАШЕМ MAC")).font(.system(size:9,weight:.semibold)).tracking(1.2) }
                    Text(L("Your files stay yours.","Ваши файлы — только ваши.")).font(.system(size:11)).foregroundStyle(.secondary)
                }.padding(.bottom,22)
            }.padding(.horizontal,20).frame(width:195).background(.ultraThinMaterial)
            Divider()
            Group {
                if model.section == "settings" { settings }
                else if model.section == "recent" { recent }
                else { converter }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(Color(nsColor:.windowBackgroundColor))
        }
        .onDrop(of:[.fileURL],isTargeted:$dropTarget) { providers in
            guard providers.count == 1, let provider=providers.first else { return false }
            _ = provider.loadObject(ofClass:URL.self) { url,_ in
                guard let url else { return }
                Task { @MainActor in model.section="convert"; model.load(url) }
            }; return true
        }
        .environment(\.locale,model.language.locale)
        .alert(L("Orbit needs your attention","Orbit: требуется внимание"),isPresented:$model.showingError) {
            Button("OK") { model.showingError=false }
        } message: { Text(model.error ?? "") }
    }

    func nav(_ section:String,_ title:String,_ symbol:String) -> some View {
        Button { model.section=section } label: {
            Label(title,systemImage:symbol).font(.system(size:13,weight:model.section == section ? .semibold : .regular))
                .frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,11).padding(.vertical,11)
                .background(model.section == section ? Color.accentColor.opacity(0.13) : .clear,in:RoundedRectangle(cornerRadius:9))
                .foregroundStyle(model.section == section ? Color.accentColor : .primary)
        }.buttonStyle(.plain)
    }

    var converter:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                HStack {
                    VStack(alignment:.leading,spacing:7) {
                        Text(L("A little gesture.\nA new format.","Один жест.\nНовый формат.")).font(.system(size:34,weight:.semibold,design:.rounded)).tracking(-1)
                        Text(L("Choose a file. Hold Shift. Find its next form.","Выберите файл. Зажмите Shift. Смените формат.")).font(.system(size:12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("⇧").font(.system(size:34,weight:.light)).foregroundStyle(Color.accentColor)
                        .frame(width:64,height:64).background(Color.accentColor.opacity(0.08),in:RoundedRectangle(cornerRadius:17))
                        .overlay(RoundedRectangle(cornerRadius:17).stroke(Color.accentColor.opacity(0.17)))
                }
                if model.file == nil { HStack(spacing:0) {
                    VStack(alignment:.leading,spacing:16) {
                        Text(L("TAKE THE SHORT WAY","КОРОТКИЙ ПУТЬ")).font(.system(size:9,weight:.semibold)).tracking(1.7).foregroundStyle(.secondary)
                        step("01",L("Select a file in Finder","Выберите файл в Finder"))
                        step("02",L("Hold ⇧ and move outward","Зажмите ⇧ и ведите курсор"))
                        step("03",L("Release to convert","Отпустите для конвертации"))
                        Text(L("⇧ Convert · ⌘ Tools · ⌃ Actions\nTab switches menus in the wheel.","⇧ Форматы · ⌘ Инструменты · ⌃ Действия\nTab переключает меню в круге.")).font(.system(size:10)).foregroundStyle(.secondary).lineSpacing(3)
                    }.padding(.leading,22).frame(width:235,alignment:.leading)
                    WheelPreview(file:model.file).frame(width:416,height:416).scaleEffect(0.66).frame(width:270,height:278).accessibilityHidden(true)
                    Spacer(minLength:0)
                }
                .frame(maxWidth:.infinity).background(Color.accentColor.opacity(0.035),in:RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18).stroke(Color.accentColor.opacity(0.09)))
                }
                fileCard
                if let file=model.file {
                    HStack {
                        Picker(L("File menu","Меню файла"),selection:$page) {
                            ForEach(WheelPage.allCases) { item in Text(item.key+" "+item.title).tag(item) }
                        }.pickerStyle(.segmented)
                        Button(L("Open wheel","Открыть круг")) { model.showWheel?(file) }
                    }.disabled(model.busy)
                    if page != .formats {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:155))],spacing:10) {
                            ForEach(Array(WheelCatalog.items(for:file,page:page).enumerated()),id:\.offset) { _,item in
                                Button { if let action=item.action { FileActions.perform(action,file:file,model:model) } } label: {
                                    HStack(spacing:9) { Image(systemName:item.symbol).font(.system(size:18)).foregroundStyle(Color.accentColor); Text(item.title).font(.system(size:10,weight:.semibold)); Spacer(minLength:0) }
                                        .padding(13).frame(maxWidth:.infinity).background(Color.accentColor.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
                                }.buttonStyle(.plain).disabled(model.busy)
                            }
                        }
                    }
                }
                if page == .formats, let file=model.file, !file.formats.isEmpty {
                    HStack {
                        Text(L("Convert to","Формат")).font(.system(size:12)).foregroundStyle(.secondary)
                        Picker("",selection:$model.selectedFormat) {
                            ForEach(file.formats) { Text($0.title).tag(Optional($0)) }
                        }.labelsHidden().frame(width:115).disabled(model.busy)
                        Spacer()
                        Button(L("Convert","Конвертировать")) { if let format=model.selectedFormat { model.convert(format) } }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.selectedFormat == nil)
                    }
                }
                if model.busy {
                    HStack { ProgressView().controlSize(.small); Text(L("Converting safely…","Конвертация…")).font(.system(size:12)); Spacer(); Button(L("Cancel","Отмена")) { model.cancel() } }
                }
                if let result=model.result {
                    HStack { Image(systemName:"checkmark.circle.fill").foregroundStyle(.green); Text(result.lastPathComponent).lineLimit(1); Spacer(); Button(L("Show in Finder","Показать в Finder")) { model.reveal(result) } }
                        .font(.system(size:12)).padding(12).background(.green.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
                }
                HStack(spacing:7) {
                    Image(systemName:"lock.shield"); Text(L("Local conversion · Originals preserved · No account","Локально · Оригиналы сохранены · Без аккаунта"))
                }.font(.system(size:10)).foregroundStyle(.secondary)
            }.padding(.horizontal,30).padding(.top,48).padding(.bottom,25)
        }
        .onChange(of:model.file?.url) { _,_ in page = .formats }
    }

    func step(_ number:String,_ title:String) -> some View {
        HStack(spacing:9) { Text(number).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(Color.accentColor); Text(title).font(.system(size:11,weight:.medium)) }
    }

    var fileCard:some View {
        HStack(spacing:13) {
            if let file=model.file {
                Image(nsImage:NSWorkspace.shared.icon(forFile:file.url.path)).resizable().frame(width:42,height:42)
                VStack(alignment:.leading,spacing:5) { Text(file.url.lastPathComponent).font(.system(size:13,weight:.medium)).lineLimit(1); Text(file.detail).font(.system(size:10)).foregroundStyle(.secondary) }
            } else {
                Image(systemName:"plus.square.dashed").font(.system(size:27,weight:.light)).foregroundStyle(Color.accentColor)
                VStack(alignment:.leading,spacing:5) { Text(L("Drop a file here","Перетащите файл сюда")).font(.system(size:13,weight:.medium)); Text(L("Images, video, audio and PDF","Изображения, видео, аудио и PDF")).font(.system(size:10)).foregroundStyle(.secondary) }
            }
            Spacer()
            if model.inspecting { ProgressView().controlSize(.small) }
            Button(L("Choose file…","Выбрать файл…")) { model.chooseFile() }.disabled(model.busy)
        }.padding(17).background(dropTarget ? Color.accentColor.opacity(0.12) : Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:13))
            .overlay(RoundedRectangle(cornerRadius:13).stroke(Color.accentColor.opacity(dropTarget ? 0.6 : 0.14)))
    }

    var settings:some View {
        Form {
            Section { Text("Orbit").font(.largeTitle.weight(.semibold)); Text(L("Small by design. Right at home on your Mac.","Маленькое приложение. Привычное на вашем Mac.")).foregroundStyle(.secondary) }
            Section(L("General","Основные")) {
                Picker(L("Language","Язык"),selection:$model.language) {
                    Text(L("System language","Язык системы")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Русский").tag(AppLanguage.russian)
                }
                Toggle(L("Launch at login","Запускать при входе в систему"),isOn:Binding(
                    get:{ model.loginStatus == .enabled || model.loginStatus == .requiresApproval },
                    set:{ model.setLoginEnabled($0) }))
                Text(L("Starts quietly in the menu bar, without opening the main window.","Запускается в строке меню, без открытия главного окна.")).font(.caption).foregroundStyle(.secondary)
                if model.loginStatus == .requiresApproval {
                    Button(L("Allow in System Settings…","Разрешить в системных настройках…")) { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section(L("Finder gesture","Жест в Finder")) {
                Text(L("Grant these permissions to use Shift in Finder. Choosing or dropping a file into Orbit works without them.","Разрешения нужны для Shift в Finder. Выбор файла и перетаскивание в окно Orbit работают без них."))
                HStack { Label(L("Accessibility · observe Shift","Универсальный доступ · клавиша Shift"),systemImage:model.accessibility ? "checkmark.circle.fill" : "circle"); Spacer(); Button(L("Enable…","Включить…")) { model.requestAccessibility() } }
                HStack { Label(L("Automation · read Finder selection","Автоматизация · выделение Finder"),systemImage:model.finderAllowed ? "checkmark.circle.fill" : "circle"); Spacer(); Button(L("Enable…","Включить…")) { model.requestFinder() } }
                Button(L("Refresh permissions","Проверить разрешения")) { model.refreshPermissions() }
                Toggle(L("Pause global gesture","Приостановить глобальный жест"),isOn:$model.gesturePaused)
                Text(L("Select exactly one file. Hold Shift, move into a sector and release Shift. During a drag, drop onto the sector instead. The center and outside the ring cancel.","Выберите ровно один файл. Зажмите Shift, наведите на сектор и отпустите Shift. При перетаскивании бросьте файл в сектор. Центр и область за кругом отменяют действие."))
                Text(L("In the wheel: ⇧ Convert · ⌘ Tools · ⌃ Actions. Tab cycles menus. During a drag you can release the key: the wheel stays open until you drop or cancel.","В круге: ⇧ — форматы, ⌘ — инструменты, ⌃ — действия. Tab переключает меню. При перетаскивании можно отпустить клавишу: круг остаётся до броска или отмены."))
            }
            Section(L("Media engine","Медиадвижок")) {
                Label(ConversionEngine.hasFFmpeg ? L("FFmpeg is ready","FFmpeg готов") : L("FFmpeg is optional","FFmpeg — дополнительный модуль"),systemImage:ConversionEngine.hasFFmpeg ? "checkmark.circle.fill" : "waveform")
                Text(L("For MP3, WAV, FLAC and more input formats, install FFmpeg using Homebrew:","Для MP3, WAV, FLAC и дополнительных входных форматов установите FFmpeg через Homebrew:"))
                Text("brew install ffmpeg").font(.system(.body,design:.monospaced)).textSelection(.enabled)
                Text(L("Without it, macOS exports compatible media to MP4, MOV and M4A.","Без него macOS экспортирует совместимые медиа в MP4, MOV и M4A."))
            }
            Section(L("Appearance & privacy","Оформление и приватность")) {
                Label(L("Follows the macOS accent color and appearance","Системный акцентный цвет, светлая и тёмная темы"),systemImage:"circle.lefthalf.filled")
                Text(L("No uploads, telemetry or stored file history. The last ten results are kept in memory until you quit. Originals are never replaced. Multi-page PDF images are saved to a new folder.","Без загрузок в сеть, телеметрии и истории на диске. Последние десять результатов хранятся в памяти до выхода. Исходники не заменяются. Страницы PDF сохраняются в новую папку."))
            }
            Section { Text("Orbit 0.3.0 · macOS 15+").foregroundStyle(.secondary) }
        }.formStyle(.grouped).padding(.top,20)
    }

    var recent:some View {
        VStack(alignment:.leading,spacing:20) {
            Text(L("Recent files","Недавние файлы")).font(.largeTitle.weight(.semibold))
            Text(L("This session only. Nothing saved to a database.","Только этот сеанс. История не сохраняется на диск.")).foregroundStyle(.secondary)
            if model.history.isEmpty { ContentUnavailableView(L("A fresh start","Пока здесь пусто"),systemImage:"clock",description:Text(L("Your converted files will appear here.","Здесь появятся результаты конвертации."))) }
            ForEach(model.history,id:\.self) { url in
                HStack { Image(systemName:"doc").foregroundStyle(Color.accentColor); Text(url.lastPathComponent).lineLimit(1); Spacer(); Button(L("Show","Показать")) { model.reveal(url) } }
                Divider()
            }
            Spacer()
        }.padding(35).padding(.top,20)
    }
}
