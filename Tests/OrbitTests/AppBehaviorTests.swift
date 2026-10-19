import XCTest
import AppKit
import Carbon
import AVFoundation
import OrbitCore
@testable import Orbit

final class AppBehaviorTests:XCTestCase {
    private var directory:URL!
    override func setUpWithError() throws {
        directory=FileManager.default.temporaryDirectory.appendingPathComponent("orbit-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at:directory) }

    private func imageFile() throws -> URL {
        let image=CGContext(data:nil,width:16,height:12,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let url=directory.appendingPathComponent("source.png")
        try ConversionEngine.writeImage(image,to:url,format:.png)
        return url
    }
    @MainActor private func finish(_ model:AppModel) async throws {
        let clock=ContinuousClock(), deadline=ContinuousClock.now.advanced(by:.seconds(5))
        while model.busy || model.inspecting {
            guard clock.now < deadline else { XCTFail("Operation did not complete"); throw CancellationError() }
            try await Task.sleep(for:.milliseconds(10))
        }
    }

    @MainActor func testBackgroundConversionDoesNotOpenMainWindow() async throws {
        let model=AppModel(), source=try imageFile()
        var opened=0; model.showWindow={ opened += 1 }
        model.convert(.jpg,file:try await ConversionEngine.inspect(source),background:true)
        try await finish(model)
        XCTAssertEqual(opened,0)
        XCTAssertEqual(model.result?.lastPathComponent,"source.jpg")
        XCTAssertFalse(model.showingError)
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
    @MainActor func testBackgroundFailureDoesNotPresentAnAlertOrOpenWindow() async throws {
        let model=AppModel(), source=try imageFile()
        var opened=0; model.showWindow={ opened += 1 }
        model.convert(.mp3,file:try await ConversionEngine.inspect(source),background:true)
        try await finish(model)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.showingError)
        XCTAssertEqual(opened,0)
        model.presentLastError()
        XCTAssertTrue(model.showingError)
        XCTAssertEqual(opened,1)
    }
    @MainActor func testForegroundErrorsRemainVisible() async throws {
        let model=AppModel(), source=try imageFile()
        model.convert(.mp3,file:try await ConversionEngine.inspect(source))
        try await finish(model)
        XCTAssertTrue(model.showingError)
        XCTAssertNotNil(model.error)
    }
    @MainActor func testUnsupportedSelectionClearsPreviousFile() async throws {
        let model=AppModel(), source=try imageFile()
        model.load(source); try await finish(model)
        XCTAssertEqual(model.file?.url,source)
        let invalid=directory.appendingPathComponent("invalid.exe")
        try Data("invalid".utf8).write(to:invalid)
        model.load(invalid)
        XCTAssertNil(model.file)
        XCTAssertNil(model.selectedFormat)
        try await finish(model)
        XCTAssertNil(model.file)
        model.convert(.jpg)
        XCTAssertFalse(model.busy)
    }
    @MainActor func testLatestInspectionWins() async throws {
        let model=AppModel(), source=try imageFile()
        let other=directory.appendingPathComponent("other.png")
        try FileManager.default.copyItem(at:source,to:other)
        model.load(source); model.load(other)
        try await finish(model)
        XCTAssertEqual(model.file?.url,other)
    }
    @MainActor func testCancelAndWaitDoesNotPublishCancelledOutput() async throws {
        let model=AppModel(), source=try imageFile()
        model.convert(.jpg,file:try await ConversionEngine.inspect(source),background:true)
        await model.cancelAndWait()
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.result)
        XCTAssertFalse(FileManager.default.fileExists(atPath:directory.appendingPathComponent("source.jpg").path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath:directory.path).contains { $0.hasPrefix(".orbit-") })
    }
    @MainActor func testWheelRejectsUnrelatedAndMultipleFiles() throws {
        _=NSApplication.shared
        let source=directory.appendingPathComponent("source.png"), other=directory.appendingPathComponent("other.png")
        let wheel=WheelView(frame:.zero)
        XCTAssertFalse(wheel.acceptsFiles([]))
        wheel.file=FileInspection(url:source,kind:.image,detail:"",formats:[.jpg])
        XCTAssertTrue(wheel.acceptsFiles([source]))
        XCTAssertFalse(wheel.acceptsFiles([other]))
        XCTAssertFalse(wheel.acceptsFiles([source,other]))
    }
    @MainActor func testLanguageDefaultsAndExplicitSelection() {
        let saved=UserDefaults.standard.object(forKey:"orbitLanguage")
        defer { UserDefaults.standard.set(saved,forKey:"orbitLanguage") }
        UserDefaults.standard.removeObject(forKey:"orbitLanguage")
        XCTAssertEqual(AppLanguage.current,.system)
        let model=AppModel()
        model.language = .english
        XCTAssertEqual(AppLanguage.current,.english)
        XCTAssertEqual(L("Choose file","Выбрать файл"),"Choose file")
        model.language = .russian
        XCTAssertEqual(L("Choose file","Выбрать файл"),"Выбрать файл")
        model.language = .system
        XCTAssertEqual(AppLanguage.current.isRussian,Locale.preferredLanguages.first?.hasPrefix("ru") == true)
    }
    @MainActor func testLoginLaunchDetection() {
        func event() -> NSAppleEventDescriptor {
            NSAppleEventDescriptor.appleEvent(withEventClass:kCoreEventClass,eventID:kAEOpenApplication,targetDescriptor:nil,returnID:AEReturnID(kAutoGenerateReturnID),transactionID:AETransactionID(kAnyTransactionID))
        }
        XCTAssertFalse(AppDelegate.isLoginLaunch(nil))
        XCTAssertFalse(AppDelegate.isLoginLaunch(event()))
        let login=event()
        login.setParam(NSAppleEventDescriptor(enumCode:keyAELaunchedAsLogInItem),forKeyword:keyAEPropData)
        XCTAssertTrue(AppDelegate.isLoginLaunch(login))
        let flagged=event()
        flagged.setParam(NSAppleEventDescriptor(boolean:true),forKeyword:keyAELaunchedAsLogInItem)
        XCTAssertTrue(AppDelegate.isLoginLaunch(flagged))
    }

    @MainActor func testFileMenusHaveRelevantToolsAndAllActions() {
        let video=FileInspection(url:directory.appendingPathComponent("video.mov"),kind:.video,hasAudio:true,detail:"",formats:[.mp4])
        let tools=WheelCatalog.items(for:video,page:.tools).compactMap(\.action)
        XCTAssertTrue(tools.contains("trim")); XCTAssertFalse(tools.contains("crop"))
        let image=FileInspection(url:directory.appendingPathComponent("image.png"),kind:.image,detail:"",formats:[.jpg])
        XCTAssertFalse(WheelCatalog.items(for:image,page:.tools).contains { $0.action == "trim" })
        XCTAssertEqual(Set(WheelCatalog.items(for:video,page:.actions).compactMap(\.action)),Set(["airdrop","float","copy","move","copyPath","terminal"]))
        XCTAssertEqual(WheelPage.formats.next,.tools); XCTAssertEqual(WheelPage.actions.next,.formats)
    }

    @MainActor func testMoveRefusesExistingDestination() throws {
        let source=try imageFile(), original=try Data(contentsOf:source)
        let folder=directory.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
        let destination=folder.appendingPathComponent(source.lastPathComponent)
        try Data("existing".utf8).write(to:destination)
        XCTAssertThrowsError(try FileActions.move(source,to:folder))
        XCTAssertEqual(try Data(contentsOf:source),original)
        XCTAssertEqual(try Data(contentsOf:destination),Data("existing".utf8))
        try FileManager.default.removeItem(at:destination)
        XCTAssertEqual(try FileActions.move(source,to:folder),destination)
        XCTAssertFalse(FileManager.default.fileExists(atPath:source.path))
        XCTAssertEqual(try Data(contentsOf:destination),original)
    }

    @MainActor func testWheelUsesNewCenterAndExposesThreeMenuButtons() {
        _=NSApplication.shared
        let wheel=WheelView(frame:NSRect(x:0,y:0,width:416,height:520))
        let file=FileInspection(url:directory.appendingPathComponent("sound.wav"),kind:.audio,hasAudio:true,detail:"",formats:[.m4a,.mp3])
        wheel.file=file; wheel.items=WheelCatalog.items(for:file,page:.formats)
        wheel.track(NSPoint(x:208,y:140)); XCTAssertEqual(wheel.hovered,0)
        wheel.track(NSPoint(x:208,y:258)); XCTAssertNil(wheel.hovered)
        let buttons=wheel.accessibilityChildren() as? [WheelAccessibilityItem] ?? []
        XCTAssertEqual(buttons.count,wheel.items.count+4)
        var selected:WheelPage?
        wheel.onPage={ selected=$0 }
        XCTAssertTrue(buttons.last!.accessibilityPerformPress())
        XCTAssertEqual(selected,.actions)
    }

    @MainActor func testTrimPreviewRangeAndWaveform() async throws {
        guard let ffmpeg=CommandRunner.executable("ffmpeg") else { throw XCTSkip("FFmpeg for test fixture") }
        let source=directory.appendingPathComponent("sound.wav")
        _=try await CommandRunner().run(ffmpeg,["-v","error","-f","lavfi","-i","sine=frequency=440:duration=1.3333",source.path])
        let file=try await ConversionEngine.inspect(source)
        let preview=MediaPreview(file:file)
        await preview.prepare()
        defer { preview.stop() }
        XCTAssertTrue(preview.ready); XCTAssertNil(preview.error)
        XCTAssertEqual(preview.waveform.count,160)
        XCTAssertGreaterThan(preview.waveform.max() ?? 0,0.9)
        XCTAssertFalse(preview.setStart(-1)); XCTAssertFalse(preview.setEnd(0))
        XCTAssertTrue(preview.setStart(0.25)); XCTAssertFalse(preview.setEnd(0.2))
        XCTAssertTrue(preview.setEnd(MediaTime.parse(MediaTime.string(preview.duration))!))
        XCTAssertLessThanOrEqual(preview.range.end,preview.duration)
        XCTAssertTrue(preview.setEnd(1))
        do {
            let model=AppModel(); var opened=0; model.showWindow={ opened += 1 }
            model.trim(file,range:preview.range,format:.m4a,muted:false)
            try await finish(model)
            XCTAssertNotNil(model.result); XCTAssertEqual(opened,0); XCTAssertFalse(model.showingError)
        }
    }

    @MainActor func testUnsupportedVideoPreviewIsRemovedOnClose() async throws {
        guard let ffmpeg=CommandRunner.executable("ffmpeg") else { throw XCTSkip("FFmpeg for test fixture") }
        let source=directory.appendingPathComponent("video.mkv")
        _=try await CommandRunner().run(ffmpeg,["-v","error","-f","lavfi","-i","testsrc2=size=96x64:rate=10:duration=0.5","-c:v","ffv1",source.path])
        if (try? await AVURLAsset(url:source).load(.isPlayable)) == true { throw XCTSkip("This OS plays FFV1 natively") }
        let temporary=FileManager.default.temporaryDirectory
        func proxies() throws -> Set<URL> {
            Set(try FileManager.default.contentsOfDirectory(at:temporary,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("orbit-preview-") })
        }
        let before=try proxies()
        let preview=MediaPreview(file:try await ConversionEngine.inspect(source))
        await preview.prepare()
        XCTAssertTrue(preview.ready); XCTAssertNil(preview.error)
        let created=try proxies().subtracting(before)
        XCTAssertEqual(created.count,1)
        preview.stop()
        for url in created { XCTAssertFalse(FileManager.default.fileExists(atPath:url.path)) }
        XCTAssertTrue(FileManager.default.fileExists(atPath:source.path))
    }
}
