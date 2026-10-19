import AppKit
import SwiftUI
import AVKit
import OrbitCore

@MainActor
final class MediaPreview:ObservableObject {
    let file:FileInspection
    let player=AVPlayer()
    @Published var duration=0.0
    @Published var range=MediaRange(start:0,end:0)
    @Published var position=0.0
    @Published var playing=false
    @Published var ready=false
    @Published var error:String?
    @Published var thumbnails:[NSImage]=[]
    @Published var waveform:[Float]=[]
    private var observer:Any?
    private var waveformTask:Task<[Float],Error>?
    private var imageGenerator:AVAssetImageGenerator?
    private var playbackDuration=0.0
    private var proxy:URL?
    private let runner=CommandRunner()
    private var closed=false
    var minimum:Double { min(0.05,duration) }

    init(file:FileInspection) { self.file=file }

    func prepare() async {
        guard !closed, !ready else { return }
        do {
            var asset=AVURLAsset(url:file.url)
            if (try? await asset.load(.isPlayable)) != true {
                guard let ffmpeg=CommandRunner.executable("ffmpeg") else { throw OrbitError.message(L("Install FFmpeg to preview this format.","Для предпросмотра этого формата нужен FFmpeg.")) }
                let url=FileManager.default.temporaryDirectory.appendingPathComponent("orbit-preview-\(UUID().uuidString).\(file.kind == .video ? "mp4" : "m4a")")
                proxy=url
                var args=["-hide_banner","-nostdin","-loglevel","error","-n","-protocol_whitelist","file,pipe","-i",file.url.path]
                if file.kind == .video {
                    args += ["-map","0:v:0","-map","0:a:0?","-vf","scale=960:540:force_original_aspect_ratio=decrease:force_divisible_by=2","-c:v","libx264","-preset","veryfast","-crf","28","-pix_fmt","yuv420p"]
                } else { args += ["-map","0:a:0","-vn"] }
                args += ["-c:a","aac","-b:a","128k",url.path]
                _=try await runner.run(ffmpeg,args)
                asset=AVURLAsset(url:url)
            }
            try Task.checkCancellation()
            guard !closed else { return }
            let seconds=try await asset.load(.duration).seconds
            playbackDuration=seconds
            duration=file.duration ?? seconds
            guard duration.isFinite, duration > 0 else { throw OrbitError.message(L("This file has no finite duration.","Не удалось определить длительность файла.")) }
            range=MediaRange(start:0,end:duration)
            player.replaceCurrentItem(with:AVPlayerItem(asset:asset))
            observer=player.addPeriodicTimeObserver(forInterval:CMTime(seconds:0.04,preferredTimescale:600),queue:.main) { [weak self] time in
                MainActor.assumeIsolated {
                    guard let self, time.seconds.isFinite else { return }
                    self.position=min(self.duration,max(0,time.seconds))
                    if self.player.rate > 0 && self.position >= self.range.end { self.player.pause() }
                    self.playing=self.player.rate > 0
                }
            }
            ready=true
            if file.kind == .video {
                let generator=AVAssetImageGenerator(asset:asset)
                imageGenerator=generator
                generator.appliesPreferredTrackTransform=true; generator.maximumSize=CGSize(width:240,height:140)
                for index in 0..<8 {
                    try Task.checkCancellation()
                    if let frame=try? await generator.image(at:CMTime(seconds:seconds*Double(index)/8,preferredTimescale:600)) {
                        guard !closed else { return }
                        thumbnails.append(NSImage(cgImage:frame.image,size:.zero))
                    }
                }
            } else {
                let url=asset.url, length=duration
                let worker=Task.detached(priority:.utility) { try await Self.readWaveform(url,duration:length) }
                waveformTask=worker
                let values=try await withTaskCancellationHandler(operation:{ try await worker.value },onCancel:{ worker.cancel() })
                if !closed { waveform=values }
            }
        } catch is CancellationError {} catch { if !closed { self.error=error.localizedDescription } }
        if closed || Task.isCancelled { cleanupProxy() }
    }

    nonisolated static func readWaveform(_ url:URL,duration:Double) async throws -> [Float] {
        guard duration.isFinite, duration > 0 else { throw OrbitError.message("Invalid audio duration.") }
        let asset=AVURLAsset(url:url)
        guard let track=try await asset.loadTracks(withMediaType:.audio).first else { return [] }
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVLinearPCMIsFloatKey:true,AVLinearPCMBitDepthKey:32,AVNumberOfChannelsKey:1,AVSampleRateKey:8000,AVLinearPCMIsNonInterleaved:false])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? OrbitError.message("Cannot read the waveform.") }
        defer { reader.cancelReading() }
        var peaks=[Float](repeating:0,count:160)
        while let sample=output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer=CMSampleBufferGetDataBuffer(sample) else { continue }
            let length=CMBlockBufferGetDataLength(buffer)
            guard length > 0, length < 4_000_000, length%MemoryLayout<Float>.size == 0 else { continue }
            var floats=[Float](repeating:0,count:length/MemoryLayout<Float>.size)
            let status=floats.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer,atOffset:0,dataLength:length,destination:$0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { continue }
            let start=CMSampleBufferGetPresentationTimeStamp(sample).seconds
            for (index,value) in floats.enumerated() where value.isFinite {
                let time=start+Double(index)/8000
                guard time.isFinite, time >= 0, time <= duration else { continue }
                let bin=min(159,max(0,Int(time/duration*160)))
                peaks[bin]=max(peaks[bin],min(1,abs(value)))
            }
        }
        if reader.status == .failed { throw reader.error ?? OrbitError.message("Cannot read the waveform.") }
        let highest=peaks.max() ?? 1
        return peaks.map { highest > 0 ? $0/highest : 0 }
    }

    func seek(_ seconds:Double) {
        position=min(duration,max(0,seconds))
        player.seek(to:CMTime(seconds:position,preferredTimescale:60000),toleranceBefore:.zero,toleranceAfter:.zero)
    }
    func togglePlayback() {
        if player.rate > 0 { player.pause(); playing=false }
        else { if position < range.start || position >= min(range.end,playbackDuration)-0.02 { seek(range.start) }; player.play(); playing=true }
    }
    @discardableResult func setStart(_ value:Double) -> Bool {
        guard value.isFinite, value >= 0, value <= range.end-minimum else { return false }
        range.start=value; player.pause(); playing=false; seek(value); return true
    }
    @discardableResult func setEnd(_ value:Double) -> Bool {
        let end=abs(value-duration) <= 0.00051 ? duration : value
        guard end.isFinite, end <= duration, end >= range.start+minimum else { return false }
        range.end=end; player.pause(); playing=false; seek(min(position,range.end)); return true
    }
    func stop() {
        closed=true; runner.cancel(); waveformTask?.cancel(); imageGenerator?.cancelAllCGImageGeneration(); player.pause(); player.replaceCurrentItem(with:nil)
        if let observer { player.removeTimeObserver(observer); self.observer=nil }
        cleanupProxy()
    }
    private func cleanupProxy() { if let proxy { try? FileManager.default.removeItem(at:proxy) } }
}

private struct TrimPlayerView:NSViewRepresentable {
    let player:AVPlayer
    func makeNSView(context:Context) -> AVPlayerView {
        let view=AVPlayerView(); view.player=player; view.controlsStyle = .none; view.videoGravity = .resizeAspect; view.allowsVideoFrameAnalysis=false
        return view
    }
    func updateNSView(_ view:AVPlayerView,context:Context) {}
}

struct MediaTrimView:View {
    let file:FileInspection
    @ObservedObject var model:AppModel
    @StateObject private var preview:MediaPreview
    @State private var format:OutputFormat
    @State private var muted=false
    @State private var validStart=true
    @State private var validEnd=true
    init(file:FileInspection,model:AppModel) {
        self.file=file; self.model=model
        _preview=StateObject(wrappedValue:MediaPreview(file:file))
        _format=State(initialValue:MediaEditing.formats(for:file).first ?? .m4a)
    }

    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text(L("Keep your favourite moment.","Оставьте нужный момент.")).font(.system(size:25,weight:.semibold,design:.rounded))
                    Text(file.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(); Image(systemName:"timeline.selection").font(.title).foregroundStyle(Color.accentColor)
            }
            ZStack {
                RoundedRectangle(cornerRadius:18).fill(Color(nsColor:.underPageBackgroundColor))
                if preview.ready {
                    if file.kind == .video { TrimPlayerView(player:preview.player).clipShape(RoundedRectangle(cornerRadius:18)) }
                    else {
                        VStack(spacing:17) {
                            Image(systemName:"waveform").font(.system(size:48,weight:.light)).foregroundStyle(Color.accentColor)
                            Text(L("Make every second count.","Каждая секунда на своём месте.")).font(.title3.weight(.medium))
                            Text(MediaTime.string(preview.duration)).font(.system(.body,design:.monospaced)).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(spacing:12) { ProgressView(); Text(L("Preparing a local preview…","Готовим локальный предпросмотр…")).font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(height:file.kind == .video ? 245 : 135)
            if preview.ready {
                HStack(spacing:14) {
                    Button { preview.togglePlayback() } label: { Image(systemName:preview.playing ? "pause.fill" : "play.fill").frame(width:20,height:20) }
                        .buttonStyle(.borderedProminent).clipShape(Circle()).keyboardShortcut(.space,modifiers:[])
                        .accessibilityLabel(preview.playing ? L("Pause","Пауза") : L("Play selection","Воспроизвести фрагмент"))
                    Text(MediaTime.string(preview.position)).font(.system(size:12,weight:.medium,design:.monospaced))
                    Text("/ "+MediaTime.string(preview.duration)).font(.system(size:12,design:.monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    Text(L("Space to play","Пробел — воспроизвести")).font(.caption).foregroundStyle(.secondary)
                }
                TrimTimeline(preview:preview).frame(height:82)
                HStack(alignment:.top,spacing:16) {
                    TimecodeField(title:L("Start","Начало"),value:preview.range.start,valid:$validStart,commit:preview.setStart)
                    TimecodeField(title:L("End","Конец"),value:preview.range.end,valid:$validEnd,commit:preview.setEnd)
                    Spacer()
                    VStack(alignment:.trailing,spacing:8) {
                        Text(L("Selected duration","Длительность фрагмента")).font(.caption).foregroundStyle(.secondary)
                        Text(MediaTime.string(preview.range.length)).font(.system(size:18,weight:.semibold,design:.monospaced)).foregroundStyle(Color.accentColor)
                    }
                }
                HStack {
                    Button(L("Start at playhead","Начало по курсору")) { preview.setStart(min(preview.position,preview.range.end-preview.minimum)) }
                    Button(L("End at playhead","Конец по курсору")) { preview.setEnd(max(preview.position,preview.range.start+preview.minimum)) }
                    Spacer()
                    Button(L("Reset","Сбросить")) { preview.range=MediaRange(start:0,end:preview.duration); preview.seek(0) }
                }.font(.caption)
                Divider()
                HStack {
                    Picker(L("Save as","Сохранить как"),selection:$format) { ForEach(MediaEditing.formats(for:file)) { Text($0.title).tag($0) } }.frame(width:185)
                    if file.kind == .video && [.mp4,.mov].contains(format) { Toggle(L("Remove audio","Без звука"),isOn:$muted).toggleStyle(.switch).controlSize(.small) }
                    Spacer()
                    Label(L("Original preserved","Оригинал сохранится"),systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error=preview.error ?? model.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3).textSelection(.enabled) }
            Spacer(minLength:0)
            HStack {
                if model.busy { ProgressView().controlSize(.small); Text(L("Saving your selection…","Сохраняем фрагмент…")).font(.caption) }
                else { Text(L("Drag the blue handles. A new file is saved beside the original.","Двигайте синие маркеры. Новый файл появится рядом с оригиналом.")).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button(model.busy ? L("Stop","Остановить") : L("Cancel","Отмена")) { if model.busy { model.cancel() } else { model.editor?.close() } }.keyboardShortcut(.cancelAction)
                Button(L("Save clip","Сохранить фрагмент")) {
                    preview.player.pause(); preview.playing=false
                    model.trim(file,range:preview.range,format:format,muted:muted && [.mp4,.mov].contains(format))
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!preview.ready || model.busy || !validStart || !validEnd)
            }
        }.padding(26).frame(width:780,height:file.kind == .video ? 690 : 580)
            .background(Color(nsColor:.windowBackgroundColor))
            .environment(\.locale,model.language.locale)
            .task { model.error=nil; await preview.prepare() }
            .onDisappear { preview.stop() }
            .onReceive(NotificationCenter.default.publisher(for:NSWindow.willCloseNotification)) { note in
                if let window=note.object as? NSWindow, window === model.editor { preview.stop() }
            }
            .onChange(of:muted) { _,value in preview.player.isMuted=value }
            .onChange(of:format) { _,value in if ![.mp4,.mov].contains(value) { muted=false } }
    }
}

private struct TimecodeField:View {
    let title:String
    let value:Double
    @Binding var valid:Bool
    let commit:(Double) -> Bool
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("00:00.000",text:$text).font(.system(size:14,weight:.medium,design:.monospaced)).textFieldStyle(.roundedBorder)
                .frame(width:145).focused($focused).accessibilityLabel(title)
                .overlay(RoundedRectangle(cornerRadius:5).stroke(valid ? Color.clear : .red))
                .onSubmit { update() }
                .onChange(of:focused) { _,isFocused in if !isFocused { update() } }
                .onChange(of:text) { _,_ in if focused { update() } }
            if !valid { Text(L("Check the time range","Проверьте время")).font(.caption2).foregroundStyle(.red) }
        }
        .onAppear { text=MediaTime.string(value) }
        .onChange(of:value) { _,newValue in
            if !focused || (MediaTime.parse(text).map { abs($0-newValue) > 0.00051 } ?? true) {
                text=MediaTime.string(newValue); valid=true
            }
        }
    }
    private func update() { valid=MediaTime.parse(text).map(commit) ?? false }
}

private struct TrimTimeline:View {
    @ObservedObject var preview:MediaPreview
    var body:some View {
        GeometryReader { geometry in
            let width=max(1,geometry.size.width-20), start=width*preview.range.start/preview.duration, end=width*preview.range.end/preview.duration
            ZStack(alignment:.topLeading) {
                ZStack {
                    RoundedRectangle(cornerRadius:9).fill(Color.accentColor.opacity(0.09))
                    if !preview.thumbnails.isEmpty {
                        HStack(spacing:0) { ForEach(preview.thumbnails.indices,id:\.self) { index in Image(nsImage:preview.thumbnails[index]).resizable().scaledToFill().frame(width:width/8,height:68).clipped() } }
                    } else {
                        Canvas { context,size in
                            let bars=preview.waveform
                            guard !bars.isEmpty else { return }
                            for (index,value) in bars.enumerated() {
                                let height=max(2,CGFloat(value)*(size.height-14))
                                let rect=CGRect(x:CGFloat(index)*size.width/CGFloat(bars.count),y:(size.height-height)/2,width:max(1,size.width/CGFloat(bars.count)-2),height:height)
                                context.fill(Path(roundedRect:rect,cornerRadius:1),with:.color(.accentColor.opacity(0.7)))
                            }
                        }
                    }
                    HStack(spacing:0) {
                        Color.black.opacity(0.4).frame(width:start)
                        Color.accentColor.opacity(0.08).frame(width:max(0,end-start))
                        Color.black.opacity(0.4)
                    }
                }.frame(width:width,height:68).clipShape(RoundedRectangle(cornerRadius:9)).offset(x:10,y:7)
                    .contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { preview.seek(($0.location.x-10)/width*preview.duration) })
                    .accessibilityElement().accessibilityLabel(L("Playhead","Позиция воспроизведения"))
                    .accessibilityValue(MediaTime.string(preview.position))
                    .accessibilityAdjustableAction { direction in preview.seek(preview.position+(direction == .increment ? 0.1 : -0.1)) }
                RoundedRectangle(cornerRadius:9).stroke(Color.accentColor,lineWidth:2).frame(width:max(0,end-start),height:68).offset(x:start+10,y:7).allowsHitTesting(false)
                Rectangle().fill(.white).frame(width:2,height:76).shadow(radius:1).offset(x:10+width*preview.position/preview.duration,y:3).allowsHitTesting(false)
                handle(start:true,width:width).offset(x:start,y:0)
                handle(start:false,width:width).offset(x:end,y:0)
            }.coordinateSpace(name:"timeline")
        }
    }
    func handle(start:Bool,width:Double) -> some View {
        Capsule().fill(Color.accentColor).frame(width:20,height:82)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width:3,height:22))
            .shadow(color:.black.opacity(0.15),radius:3,y:1)
            .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("timeline")).onChanged { event in
                let value=min(preview.duration,max(0,(event.location.x-10)/width*preview.duration))
                if start { preview.setStart(min(value,preview.range.end-preview.minimum)) }
                else { preview.setEnd(max(value,preview.range.start+preview.minimum)) }
            })
            .accessibilityElement().accessibilityLabel(start ? L("Trim start","Начало фрагмента") : L("Trim end","Конец фрагмента"))
            .accessibilityValue(MediaTime.string(start ? preview.range.start : preview.range.end))
            .accessibilityAdjustableAction { direction in
                let step=direction == .increment ? 0.1 : -0.1
                if start { preview.setStart(preview.range.start+step) } else { preview.setEnd(preview.range.end+step) }
            }
    }
}
