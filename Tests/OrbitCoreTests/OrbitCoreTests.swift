import XCTest
import AppKit
import PDFKit
@testable import OrbitCore

final class OrbitCoreTests:XCTestCase {
    var directory:URL!
    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("orbit-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }

    func testWheelCardinalDirectionsAndDeadZone() {
        XCTAssertEqual(RadialGeometry.sector(x:0,y:-100,count:4),0)
        XCTAssertEqual(RadialGeometry.sector(x:100,y:0,count:4),1)
        XCTAssertEqual(RadialGeometry.sector(x:0,y:100,count:4),2)
        XCTAssertEqual(RadialGeometry.sector(x:-100,y:0,count:4),3)
        XCTAssertNil(RadialGeometry.sector(x:0,y:0,count:6))
        XCTAssertNil(RadialGeometry.sector(x:180,y:0,count:6))
        XCTAssertNil(RadialGeometry.sector(x:100,y:0,count:0))
        XCTAssertEqual(RadialGeometry.sector(x:0,y:-100,count:1),0)
    }
    func testCatalogNeverOffersTextForVideoOrVideoForAudio() {
        let video=FormatCatalog.formats(kind:.video,sourceExtension:"MOV",hasAudio:true,ffmpeg:true)
        XCTAssertTrue(video.contains(.mp4)); XCTAssertTrue(video.contains(.mp3))
        XCTAssertFalse(video.contains(.txt)); XCTAssertFalse(video.contains(.mov))
        XCTAssertFalse(FormatCatalog.formats(kind:.audio,sourceExtension:"wav",hasAudio:true,ffmpeg:true).contains(.mp4))
        XCTAssertFalse(FormatCatalog.formats(kind:.video,sourceExtension:"mov",hasAudio:false,ffmpeg:true).contains(.mp3))
        XCTAssertFalse(FormatCatalog.formats(kind:.video,sourceExtension:"mov",hasAudio:true,ffmpeg:false).contains(.mp3))
        XCTAssertFalse(FormatCatalog.formats(kind:.image,sourceExtension:"JPEG",hasAudio:false,ffmpeg:false).contains(.jpg))
    }
    func makeImage() throws -> CGImage {
        let context=CGContext(data:nil,width:32,height:20,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0,green:0.5,blue:1,alpha:0.5));context.fill(CGRect(x:0,y:0,width:32,height:20))
        return context.makeImage()!
    }
    func testActualImageInspectionAndConversionPreserveSource() async throws {
        let source=directory.appendingPathComponent("sample.png")
        try ConversionEngine.writeImage(makeImage(),to:source,format:.png)
        let original=try Data(contentsOf:source)
        let file=try await ConversionEngine.inspect(source)
        XCTAssertEqual(file.kind,.image)
        for format in file.formats {
            let output=try await ConversionEngine.convert(file,to:format,runner:CommandRunner())
            XCTAssertTrue(FileManager.default.fileExists(atPath:output.path))
            if format == .pdf { XCTAssertEqual(PDFDocument(url:output)?.pageCount,1) }
            else { XCTAssertEqual(try ConversionEngine.loadImage(output).width,32) }
        }
        XCTAssertEqual(try Data(contentsOf:source),original)
    }
    func testNoOverwriteIncludingExistingResult() async throws {
        let source=directory.appendingPathComponent("sample.png")
        try ConversionEngine.writeImage(makeImage(),to:source,format:.png)
        let existing=directory.appendingPathComponent("sample.jpg")
        let sentinel=Data("do not replace".utf8);try sentinel.write(to:existing)
        let file=try await ConversionEngine.inspect(source)
        let output=try await ConversionEngine.convert(file,to:.jpg,runner:CommandRunner())
        XCTAssertEqual(output.lastPathComponent,"sample 2.jpg")
        XCTAssertEqual(try Data(contentsOf:existing),sentinel)
    }
    func testPublishFailsRatherThanReplacingDestination() throws {
        let source=directory.appendingPathComponent("input.png")
        let temp=directory.appendingPathComponent(".temp")
        try Data("new".utf8).write(to:temp)
        let output=try OutputFiles.publish(temp,beside:source,extension:"jpg")
        XCTAssertEqual(output.lastPathComponent,"input.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath:temp.path))
    }
    func testPDFExportsEveryPageAndText() async throws {
        let document=PDFDocument()
        for index in 0..<2 {
            let page=PDFPage(image:NSImage(cgImage:try makeImage(),size:.zero))!
            let annotation=PDFAnnotation(bounds:CGRect(x:0,y:0,width:10,height:10),forType:.text,withProperties:nil)
            annotation.contents="Page \(index)";page.addAnnotation(annotation)
            document.insert(page,at:index)
        }
        let source=directory.appendingPathComponent("document.pdf");XCTAssertTrue(document.write(to:source))
        let file=try await ConversionEngine.inspect(source)
        let output=try await ConversionEngine.convert(file,to:.png,runner:CommandRunner())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:output,includingPropertiesForKeys:nil).count,2)
        do { _=try await ConversionEngine.convert(file,to:.txt,runner:CommandRunner());XCTFail("Scanned PDF must not produce an empty TXT") }
        catch { XCTAssertTrue(error.localizedDescription.contains("OCR")) }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath:directory.path).allSatisfy { !$0.hasPrefix(".orbit-") })
    }
    func testRejectFolderAndUnsupportedFile() async throws {
        do { _=try await ConversionEngine.inspect(directory);XCTFail() } catch {}
        let file=directory.appendingPathComponent("file.exe");try Data([1,2]).write(to:file)
        do { _=try await ConversionEngine.inspect(file);XCTFail() } catch {}
        let broken=directory.appendingPathComponent("fake.mov");try Data("not a video".utf8).write(to:broken)
        do { _=try await ConversionEngine.inspect(broken);XCTFail() } catch {}
    }
    func testRejectInvalidRouteAndCleanUp() async throws {
        let source=directory.appendingPathComponent("image.png")
        try ConversionEngine.writeImage(makeImage(),to:source,format:.png)
        let file=try await ConversionEngine.inspect(source)
        do { _=try await ConversionEngine.convert(file,to:.mp3,runner:CommandRunner());XCTFail() } catch {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path).count,1)
    }
    func testMediaArgumentsTreatFilenameAsData() {
        let source=directory.appendingPathComponent("a $(touch nope); 'video.mov")
        let output=directory.appendingPathComponent("out.mp3")
        let args=ConversionEngine.mediaArguments(input:source,output:output,format:.mp3)
        XCTAssertTrue(args.contains(source.path));XCTAssertEqual(args.last,output.path)
        XCTAssertTrue(args.contains("-n"));XCTAssertTrue(args.contains("file,pipe"))
    }
    func testCancellationBeforeProcessLaunch() async throws {
        let runner=CommandRunner(); runner.cancel()
        do { _=try await runner.run(URL(fileURLWithPath:"/usr/bin/true"),[]);XCTFail() }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRealMovieToMP4AndMP3() async throws {
        guard let ffmpeg=CommandRunner.executable("ffmpeg"), ConversionEngine.hasFFmpeg else { throw XCTSkip("FFmpeg not installed") }
        let source=directory.appendingPathComponent("sample 'with spaces.mov")
        _=try await CommandRunner().run(ffmpeg,["-v","error","-f","lavfi","-i","testsrc2=size=64x48:rate=10:duration=0.4","-f","lavfi","-i","sine=frequency=440:duration=0.4","-c:v","libx264","-c:a","aac","-shortest",source.path])
        let original=try Data(contentsOf:source)
        let file=try await ConversionEngine.inspect(source)
        XCTAssertEqual(file.kind,.video);XCTAssertTrue(file.hasAudio)
        for format:OutputFormat in [.mp4,.mp3,.m4a,.wav,.flac] {
            let output=try await ConversionEngine.convert(file,to:format,runner:CommandRunner())
            let inspection=try await ConversionEngine.inspect(output)
            XCTAssertEqual(inspection.kind,format == .mp4 ? .video : .audio)
            XCTAssertGreaterThan(try Data(contentsOf:output).count,100)
        }
        XCTAssertEqual(original,try Data(contentsOf:source))
    }
    func testAlbumArtworkDoesNotTurnAudioIntoVideo() async throws {
        guard let ffmpeg=CommandRunner.executable("ffmpeg"), ConversionEngine.hasFFmpeg else { throw XCTSkip("FFmpeg not installed") }
        let cover=directory.appendingPathComponent("cover.jpg")
        try ConversionEngine.writeImage(makeImage(),to:cover,format:.jpg)
        let source=directory.appendingPathComponent("album.mp3")
        _=try await CommandRunner().run(ffmpeg,["-v","error","-f","lavfi","-i","sine=frequency=440:duration=0.3","-i",cover.path,"-map","0:a","-map","1:v","-c:a","libmp3lame","-c:v","copy","-disposition:v","attached_pic",source.path])
        let file=try await ConversionEngine.inspect(source)
        XCTAssertEqual(file.kind,.audio)
        XCTAssertFalse(file.formats.contains(.mp4))
    }
    func testRunningProcessCancellation() async throws {
        let runner=CommandRunner()
        let task=Task { try await runner.run(URL(fileURLWithPath:"/bin/sleep"),["20"]) }
        try await Task.sleep(for:.milliseconds(80))
        task.cancel()
        do { _=try await task.value;XCTFail("Cancelled process returned success") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testSilentVideoDoesNotOfferAudio() async throws {
        guard let ffmpeg=CommandRunner.executable("ffmpeg"), ConversionEngine.hasFFmpeg else { throw XCTSkip("FFmpeg not installed") }
        let source=directory.appendingPathComponent("silent.mov")
        _=try await CommandRunner().run(ffmpeg,["-v","error","-f","lavfi","-i","color=size=64x48:duration=0.2","-c:v","libx264",source.path])
        let file=try await ConversionEngine.inspect(source)
        XCTAssertFalse(file.hasAudio);XCTAssertFalse(file.formats.contains(.mp3))
    }
}
