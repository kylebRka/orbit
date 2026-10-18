import XCTest
import AppKit
import Carbon
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
}
