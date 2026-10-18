import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum FileKind: String, Sendable { case image, pdf, video, audio }

public enum OutputFormat: String, CaseIterable, Sendable, Identifiable {
    case png, jpg, heic, tiff, bmp, pdf, mp4, mov, mp3, m4a, wav, flac, txt
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
    public var symbol: String {
        switch self {
        case .mp4, .mov: return "film"
        case .mp3, .m4a, .wav, .flac: return "waveform"
        case .pdf, .txt: return "doc.text"
        default: return "photo"
        }
    }
    public var imageType: CFString? {
        switch self {
        case .png: return UTType.png.identifier as CFString
        case .jpg: return UTType.jpeg.identifier as CFString
        case .heic: return UTType.heic.identifier as CFString
        case .tiff: return UTType.tiff.identifier as CFString
        case .bmp: return UTType.bmp.identifier as CFString
        default: return nil
        }
    }
}

public struct FileInspection: Sendable {
    public let url: URL
    public let kind: FileKind
    public let hasAudio: Bool
    public let detail: String
    public let formats: [OutputFormat]
    public init(url: URL, kind: FileKind, hasAudio: Bool = false, detail: String, formats: [OutputFormat]) {
        self.url = url; self.kind = kind; self.hasAudio = hasAudio; self.detail = detail; self.formats = formats
    }
}

public enum FormatCatalog {
    public static func formats(kind: FileKind, sourceExtension: String, hasAudio: Bool, ffmpeg: Bool) -> [OutputFormat] {
        let formats: [OutputFormat]
        switch kind {
        case .image:
            let writable = CGImageDestinationCopyTypeIdentifiers() as! [String]
            formats = [.png, .jpg, .heic, .tiff, .bmp, .pdf].filter {
                $0 == .pdf || $0.imageType.map { writable.contains($0 as String) } == true
            }
        case .pdf: formats = [.png, .jpg, .txt]
        case .video: formats = ffmpeg ? [.mp4, .mov] + (hasAudio ? [.mp3, .m4a, .wav, .flac] : []) : [.mp4, .mov] + (hasAudio ? [.m4a] : [])
        case .audio: formats = ffmpeg ? [.mp3, .m4a, .wav, .flac] : [.m4a]
        }
        let ext = sourceExtension.lowercased() == "jpeg" ? "jpg" : sourceExtension.lowercased() == "tif" ? "tiff" : sourceExtension.lowercased()
        return formats.filter { $0.rawValue != ext }
    }
}

public enum OrbitError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

public enum OutputFiles {
    public static func availableURL(beside source: URL, extension ext: String, suffix: String = "") -> URL {
        let directory = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent + suffix
        var candidate = directory.appendingPathComponent(stem).appendingPathExtension(ext)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(number)").appendingPathExtension(ext)
            number += 1
        }
        return candidate
    }

    /// Move fails if another writer has taken the destination; never replace an existing file.
    public static func publish(_ temporary: URL, beside source: URL, extension ext: String, suffix: String = "") throws -> URL {
        let result = availableURL(beside: source, extension: ext, suffix: suffix)
        try FileManager.default.moveItem(at: temporary, to: result)
        return result
    }
}
