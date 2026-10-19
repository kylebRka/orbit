import Foundation

public struct MediaRange: Sendable, Equatable {
    public var start:Double
    public var end:Double
    public var length:Double { end-start }
    public init(start:Double,end:Double) { self.start=start; self.end=end }
    public func validate(duration:Double) throws {
        guard duration.isFinite, duration > 0, start.isFinite, end.isFinite,
              start >= 0, end <= duration, end > start else { throw OrbitError.message("Choose a valid start and end within the file's duration.") }
    }
}

public enum MediaTime {
    public static func string(_ seconds:Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < 360_000_000 else { return "00:00.000" }
        let total=Int((seconds*1000).rounded())
        let ms=total%1000, s=(total/1000)%60, m=(total/60000)%60, h=total/3600000
        return h > 0 ? String(format:"%02d:%02d:%02d.%03d",h,m,s,ms) : String(format:"%02d:%02d.%03d",m,s,ms)
    }
    public static func parse(_ text:String) -> Double? {
        let parts=text.trimmingCharacters(in:.whitespacesAndNewlines).replacingOccurrences(of:",",with:".").split(separator:":",omittingEmptySubsequences:false)
        guard (1...3).contains(parts.count) else { return nil }
        var total=0.0
        for (index,part) in parts.enumerated() {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  let value=Double(part), value.isFinite, value >= 0,
                  (index == parts.count-1 || !part.contains(".")), (index == 0 || value < 60) else { return nil }
            total=total*60+value
        }
        return total.isFinite && total < 360_000_000 ? total : nil
    }
}

public enum MediaEditing {
    public static func formats(for file:FileInspection, ffmpeg:Bool = ConversionEngine.hasFFmpeg) -> [OutputFormat] {
        guard file.kind == .video || file.kind == .audio else { return [] }
        let video:[OutputFormat]=file.kind == .video ? [.mp4,.mov] : []
        let audio:[OutputFormat]=file.hasAudio || file.kind == .audio ? (ffmpeg ? [.m4a,.mp3,.wav,.flac] : [.m4a]) : []
        return video+audio
    }

    public static func trim(_ file:FileInspection, range:MediaRange, format:OutputFormat, muted:Bool = false,
                            runner:CommandRunner, useFFmpeg:Bool = ConversionEngine.hasFFmpeg) async throws -> URL {
        let current=try await ConversionEngine.inspect(file.url)
        guard let duration=current.duration, formats(for:current,ffmpeg:useFFmpeg).contains(format),
              !muted || (current.kind == .video && [.mp4,.mov].contains(format)) else { throw OrbitError.message("This media cannot be trimmed to the selected format.") }
        try range.validate(duration:duration)
        try Task.checkCancellation()
        let temporary=file.url.deletingLastPathComponent().appendingPathComponent(".orbit-\(UUID().uuidString).\(format.rawValue)")
        defer { try? FileManager.default.removeItem(at:temporary) }
        try await ConversionEngine.exportMedia(current,to:temporary,format:format,runner:runner,range:range,muted:muted,useFFmpeg:useFFmpeg)
        try Task.checkCancellation()
        return try OutputFiles.publish(temporary,beside:file.url,extension:format.rawValue,suffix:"-trimmed")
    }
}
