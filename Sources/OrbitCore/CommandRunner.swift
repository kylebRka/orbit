import Foundation

public final class CommandRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public static func executable(_ name: String) -> URL? {
        let paths = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/\(name)").path,
                     "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    public func cancel() {
        lock.lock(); cancelled = true
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }

    public func run(_ executable: URL, _ arguments: [String]) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { continuation.resume(returning: try self.runBlocking(executable, arguments)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { self.cancel() })
    }

    private func runBlocking(_ executable: URL, _ arguments: [String]) throws -> Data {
        let task = Process()
        let pipe = Pipe()
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? logHandle.close(); try? FileManager.default.removeItem(at: log) }
        task.executableURL = executable
        task.arguments = arguments
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = pipe
        task.standardError = logHandle
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        process = task
        do { try task.run() } catch { process = nil; lock.unlock(); throw error }
        lock.unlock()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        lock.lock(); process = nil; let wasCancelled = cancelled; lock.unlock()
        if wasCancelled { throw CancellationError() }
        guard task.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: log)) ?? Data()
            let tail = String(decoding: data.suffix(1800), as: UTF8.self)
            throw OrbitError.message(tail.isEmpty ? "Conversion failed (\(task.terminationStatus))." : tail)
        }
        return output
    }
}
