import AppKit
import AVFoundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

public enum ConversionEngine {
    public static var hasFFmpeg: Bool { CommandRunner.executable("ffmpeg") != nil && CommandRunner.executable("ffprobe") != nil }

    public static func inspect(_ url: URL) async throws -> FileInspection {
        guard url.isFileURL else { throw OrbitError.message("Choose a local file.") }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw OrbitError.message("Choose a file, not a folder.") }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw OrbitError.message("This file cannot be read. Check its permissions.") }
        let ext = url.pathExtension.lowercased()
        let kind: FileKind
        var audio = false
        var detail: String
        let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil)
        let isPDF = ext == "pdf" || imageSource.flatMap { CGImageSourceGetType($0) }.map { ($0 as String) == UTType.pdf.identifier } == true
        if isPDF {
            guard let pdf = PDFDocument(url: url) else { throw OrbitError.message("This PDF is damaged or unsupported.") }
            guard !pdf.isEncrypted else { throw OrbitError.message("Unlock this PDF before converting it.") }
            guard pdf.pageCount > 0 else { throw OrbitError.message("This PDF has no pages.") }
            kind = .pdf; detail = "\(pdf.pageCount) pages"
        } else if let source = imageSource, CGImageSourceGetCount(source) > 0 {
            guard CGImageSourceGetCount(source) == 1 else { throw OrbitError.message("Animated and multipage images are not supported yet. Export a single frame first.") }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            let width = properties?[kCGImagePropertyPixelWidth as String] as? Int ?? 0
            let height = properties?[kCGImagePropertyPixelHeight as String] as? Int ?? 0
            guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else { throw OrbitError.message("Images must be under 100 megapixels.") }
            guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else { throw OrbitError.message("The image is damaged or unsupported.") }
            kind = .image; detail = "\(width) × \(height)"
        } else {
            let media = ["mov", "mp4", "m4v", "mkv", "webm", "avi", "mpg", "mpeg", "mp3", "m4a", "wav", "aif", "aiff", "flac", "ogg", "aac", "opus"]
            guard media.contains(ext) else { throw OrbitError.message("Unsupported file. Choose an image, PDF, video or audio file.") }
            if hasFFmpeg, let probe = CommandRunner.executable("ffprobe") {
                let data = try await CommandRunner().run(probe, ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries", "stream=codec_type:stream_disposition=attached_pic:format=duration", "-of", "json", url.path])
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let streams = json?["streams"] as? [[String: Any]] ?? []
                let video = streams.contains {
                    $0["codec_type"] as? String == "video" && ($0["disposition"] as? [String: Any])?["attached_pic"] as? Int != 1
                }
                audio = streams.contains { $0["codec_type"] as? String == "audio" }
                guard video || audio else { throw OrbitError.message("No playable audio or video tracks found.") }
                kind = video ? .video : .audio
            } else {
                let asset = AVURLAsset(url: url)
                let video = try await !asset.loadTracks(withMediaType: .video).isEmpty
                audio = try await !asset.loadTracks(withMediaType: .audio).isEmpty
                guard video || audio else { throw OrbitError.message("This media needs FFmpeg. Install it with: brew install ffmpeg") }
                kind = video ? .video : .audio
            }
            detail = kind == .video ? (audio ? "Video + audio" : "Video · no audio") : "Audio"
        }
        let size = ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)
        return FileInspection(url: url, kind: kind, hasAudio: audio, detail: "\(detail) · \(size)",
                              formats: FormatCatalog.formats(kind: kind, sourceExtension: ext, hasAudio: audio, ffmpeg: hasFFmpeg))
    }

    public static func convert(_ file: FileInspection, to format: OutputFormat, runner: CommandRunner) async throws -> URL {
        guard file.formats.contains(format) else { throw OrbitError.message("This format is not available for the selected file.") }
        let isPages = file.kind == .pdf && format != .txt
        let temporary = file.url.deletingLastPathComponent().appendingPathComponent(".orbit-\(UUID().uuidString)\(isPages ? "" : "." + format.rawValue)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        switch file.kind {
        case .image:
            try writeImage(loadImage(file.url), to: temporary, format: format)
        case .pdf:
            guard let document = PDFDocument(url: file.url), !document.isEncrypted else { throw OrbitError.message("Cannot open this PDF.") }
            if format == .txt {
                guard let text = document.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw OrbitError.message("This PDF has no text layer. Scanned pages need OCR, which is not included yet.")
                }
                try text.write(to: temporary, atomically: true, encoding: .utf8)
            } else {
                try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
                for index in 0..<document.pageCount {
                    try Task.checkCancellation()
                    guard let page = document.page(at: index) else { throw OrbitError.message("Cannot read PDF page \(index + 1).") }
                    let bounds = page.bounds(for: .mediaBox)
                    let scale = min(2, 4096 / max(bounds.width, bounds.height))
                    let size = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
                    guard let image = page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw OrbitError.message("Cannot render PDF page.") }
                    try writeImage(image, to: temporary.appendingPathComponent(String(format:"Page %03d.%@", index + 1, format.rawValue)), format: format)
                }
            }
        case .audio, .video:
            if hasFFmpeg, let executable = CommandRunner.executable("ffmpeg") {
                _ = try await runner.run(executable, mediaArguments(input: file.url, output: temporary, format: format))
            } else {
                let asset = AVURLAsset(url: file.url)
                let preset = format == .m4a ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
                guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw OrbitError.message("This media cannot be exported by macOS. Install FFmpeg.") }
                let type: AVFileType = format == .m4a ? .m4a : format == .mov ? .mov : .mp4
                try await session.export(to: temporary, as: type)
            }
        }
        try Task.checkCancellation()
        return try OutputFiles.publish(temporary, beside: file.url, extension: isPages ? "pages" : format.rawValue,
                                       suffix: isPages ? "-\(format.rawValue)" : "")
    }

    public static func mediaArguments(input: URL, output: URL, format: OutputFormat) -> [String] {
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "error", "-n", "-protocol_whitelist", "file,pipe", "-i", input.path]
        switch format {
        case .mp4, .mov:
            arguments += ["-map", "0:v:0", "-map", "0:a:0?", "-c:v", "libx264", "-crf", "20", "-preset", "medium", "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        case .mp3: arguments += ["-map", "0:a:0", "-vn", "-c:a", "libmp3lame", "-q:a", "2"]
        case .m4a: arguments += ["-map", "0:a:0", "-vn", "-c:a", "aac", "-b:a", "192k"]
        case .wav: arguments += ["-map", "0:a:0", "-vn", "-c:a", "pcm_s16le"]
        case .flac: arguments += ["-map", "0:a:0", "-vn", "-c:a", "flac"]
        default: break
        }
        return arguments + [output.path]
    }

    public static func loadImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { throw OrbitError.message("Cannot decode this image.") }
        guard width > 0, height > 0, Double(width) * Double(height) <= 100_000_000 else { throw OrbitError.message("Images must be under 100 megapixels.") }
        // ImageIO applies EXIF orientation while preserving the original pixel dimensions.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                       kCGImageSourceCreateThumbnailWithTransform: true,
                                       kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw OrbitError.message("Cannot decode this image.") }
        return image
    }

    public static func writeImage(_ image: CGImage, to url: URL, format: OutputFormat, quality: Double = 0.9) throws {
        if format == .pdf {
            var box = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { throw OrbitError.message("Cannot create PDF.") }
            context.beginPDFPage(nil); context.draw(image, in: box); context.endPDFPage(); context.closePDF()
            return
        }
        guard let type = format.imageType, let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { throw OrbitError.message("This image format is not available on your Mac.") }
        var encoded = image
        if format == .jpg || format == .bmp {
            guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw OrbitError.message("Cannot prepare image.") }
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x:0, y:0, width:image.width, height:image.height))
            context.draw(image, in: CGRect(x:0, y:0, width:image.width, height:image.height))
            guard let flattened = context.makeImage() else { throw OrbitError.message("Cannot prepare image.") }
            encoded = flattened
        }
        CGImageDestinationAddImage(destination, encoded, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw OrbitError.message("Cannot write the converted image.") }
    }
}
