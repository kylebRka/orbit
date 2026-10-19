import XCTest
@testable import OrbitCore

final class MediaEditingTests:XCTestCase {
    private var directory:URL!
    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("orbit-trim-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }

    func testTimecodeParsingAndRounding() {
        XCTAssertEqual(MediaTime.parse("01:02:03.125"),3723.125)
        XCTAssertEqual(MediaTime.parse(" 02:04,5 "),124.5)
        XCTAssertEqual(MediaTime.parse("93.25"),93.25)
        XCTAssertEqual(MediaTime.string(59.9996),"01:00.000")
        XCTAssertEqual(MediaTime.string(3723.125),"01:02:03.125")
        for text in ["", "NaN", "inf", "-1", "1:60", "1::2", "1:2:3:4", "1.5:02", "1e3", "1;rm", ".", "١٢"] {
            XCTAssertNil(MediaTime.parse(text),text)
        }
        XCTAssertEqual(MediaTime.string(.infinity),"00:00.000")
    }

    func testRangeRejectsInvalidNumbersAndBounds() throws {
        try MediaRange(start:0,end:10).validate(duration:10)
        for range in [MediaRange(start:-1,end:2),MediaRange(start:2,end:2),MediaRange(start:3,end:2),MediaRange(start:0,end:11),MediaRange(start:.nan,end:1),MediaRange(start:0,end:.infinity)] {
            XCTAssertThrowsError(try range.validate(duration:10))
        }
        XCTAssertThrowsError(try MediaRange(start:0,end:1).validate(duration:.nan))
    }

    func testTrimCatalogIncludesSameFormatAndRespectsSilentVideo() {
        let video=FileInspection(url:URL(fileURLWithPath:"/movie.mp4"),kind:.video,detail:"",formats:[.mov])
        XCTAssertEqual(MediaEditing.formats(for:video,ffmpeg:true),[.mp4,.mov])
        let audio=FileInspection(url:URL(fileURLWithPath:"/sound.m4a"),kind:.audio,hasAudio:true,detail:"",formats:[])
        XCTAssertTrue(MediaEditing.formats(for:audio,ffmpeg:true).contains(.m4a))
        XCTAssertEqual(MediaEditing.formats(for:audio,ffmpeg:false),[.m4a])
    }

    func testTrimArgumentsUseAccurateSeekAndKeepPathsAsData() {
        let input=directory.appendingPathComponent("' $(bad); movie.mov"), output=directory.appendingPathComponent("out.mp4")
        let args=ConversionEngine.mediaArguments(input:input,output:output,format:.mp4,range:MediaRange(start:1.25,end:2.75),muted:true)
        XCTAssertEqual(args[args.firstIndex(of:"-ss")!+1],"1.25")
        XCTAssertLessThan(args.firstIndex(of:"-ss")!,args.firstIndex(of:"-i")!)
        XCTAssertEqual(args[args.firstIndex(of:"-t")!+1],"1.5")
        XCTAssertTrue(args.contains(input.path)); XCTAssertTrue(args.contains("-an"))
        XCTAssertFalse(args.contains("copy")); XCTAssertEqual(args.last,output.path)
    }

    private func fixture(video:Bool) async throws -> FileInspection {
        guard let ffmpeg=CommandRunner.executable("ffmpeg"),ConversionEngine.hasFFmpeg else { throw XCTSkip("FFmpeg required for media fixtures") }
        let url=directory.appendingPathComponent(video ? "source 'video.mov" : "source 'audio.wav")
        var args=["-v","error"]
        if video { args += ["-f","lavfi","-i","testsrc2=size=96x64:rate=20:duration=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-c:a","aac","-shortest"] }
        else { args += ["-f","lavfi","-i","sine=frequency=440:duration=2","-c:a","pcm_s16le"] }
        _=try await CommandRunner().run(ffmpeg,args+[url.path])
        return try await ConversionEngine.inspect(url)
    }

    func testRealVideoAndAudioTrimPreserveSourcesAndExistingOutput() async throws {
        for video in [true,false] {
            let file=try await fixture(video:video), original=try Data(contentsOf:file.url)
            let format:OutputFormat=video ? .mp4 : .wav
            let occupied=file.url.deletingPathExtension().appendingPathExtension(format.rawValue)
            // Existing result must never be replaced, including the same source format.
            let existing=file.url.deletingLastPathComponent().appendingPathComponent(file.url.deletingPathExtension().lastPathComponent+"-trimmed").appendingPathExtension(format.rawValue)
            try Data("keep me".utf8).write(to:existing)
            let output=try await MediaEditing.trim(file,range:MediaRange(start:0.35,end:1.15),format:format,runner:CommandRunner())
            let result=try await ConversionEngine.inspect(output)
            XCTAssertEqual(result.duration ?? 0,0.8,accuracy:0.12)
            XCTAssertEqual(result.kind,video ? .video : .audio); XCTAssertTrue(result.hasAudio)
            XCTAssertNotEqual(output,occupied)
            XCTAssertTrue(output.lastPathComponent.contains("-trimmed 2"))
            XCTAssertEqual(try Data(contentsOf:existing),Data("keep me".utf8))
            XCTAssertEqual(try Data(contentsOf:file.url),original)
        }
    }

    func testTrimCanRemoveVideoAudioAndExtractAudioRange() async throws {
        let file=try await fixture(video:true)
        let muted=try await MediaEditing.trim(file,range:MediaRange(start:0.2,end:1.2),format:.mp4,muted:true,runner:CommandRunner())
        let mutedInfo=try await ConversionEngine.inspect(muted)
        XCTAssertFalse(mutedInfo.hasAudio)
        let audio=try await MediaEditing.trim(file,range:MediaRange(start:0.5,end:1.25),format:.mp3,runner:CommandRunner())
        let audioInfo=try await ConversionEngine.inspect(audio)
        XCTAssertEqual(audioInfo.kind,.audio); XCTAssertEqual(audioInfo.duration ?? 0,0.75,accuracy:0.1)
    }

    func testNativeTrimmingWithoutFFmpegExport() async throws {
        let file=try await fixture(video:true)
        for format:OutputFormat in [.mp4,.m4a] {
            let output=try await MediaEditing.trim(file,range:MediaRange(start:0.25,end:1.25),format:format,muted:format == .mp4,runner:CommandRunner(),useFFmpeg:false)
            let info=try await ConversionEngine.inspect(output)
            XCTAssertEqual(info.duration ?? 0,1,accuracy:0.1)
            XCTAssertEqual(info.hasAudio,format == .m4a)
        }
    }

    func testInvalidAndCancelledTrimsLeaveNoTemporaryOutput() async throws {
        let file=try await fixture(video:false)
        for range in [MediaRange(start:-0.1,end:1),MediaRange(start:0,end:10)] {
            do { _=try await MediaEditing.trim(file,range:range,format:.m4a,runner:CommandRunner()); XCTFail("Invalid range accepted") } catch {}
        }
        let runner=CommandRunner(); runner.cancel()
        do { _=try await MediaEditing.trim(file,range:MediaRange(start:0,end:1),format:.m4a,runner:runner); XCTFail("Cancelled trim published output") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:directory.path),[file.url.lastPathComponent])
    }
}
