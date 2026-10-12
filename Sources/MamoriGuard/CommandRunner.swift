import Foundation
import Darwin

struct CommandResult: Sendable {
    let code: Int32
    let output: String
    let error: String
}

enum GuardFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { "Guard operation failed." } }
}

protocol GuardCommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], input: String?) throws -> CommandResult
}

extension GuardCommandRunning {
    func run(_ executable: String, _ arguments: [String]) throws -> CommandResult { try run(executable, arguments, input: nil) }
    func pf(_ arguments: [String], input: String? = nil) throws -> String {
        let result = try run("/sbin/pfctl", arguments, input: input)
        guard result.code == 0 else { throw GuardFailure.message("PF could not complete the requested operation (\(result.code)).") }
        return result.output
    }
}

private final class BoundedOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private var exceeded = false
    func drain(_ handle: FileHandle) {
        while let data = try? handle.read(upToCount: 16_384), !data.isEmpty {
            lock.lock()
            if bytes.count + data.count <= 1_048_576 { bytes.append(data) }
            else { exceeded = true }
            lock.unlock()
        }
    }
    func result() throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard !exceeded else { throw GuardFailure.message("A system command returned more data than the guard can safely inspect.") }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Fixed argv only. Both pipes drain concurrently; a child cannot deadlock on stderr.
struct ProcessCommandRunner: GuardCommandRunning {
    func run(_ executable: String, _ arguments: [String], input: String?) throws -> CommandResult {
        let process = Process(), stdout = Pipe(), stderr = Pipe(), stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C", "LANG": "C"]
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let output = BoundedOutput(), errors = BoundedOutput(), readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async { output.drain(stdout.fileHandleForReading); readers.leave() }
        readers.enter()
        DispatchQueue.global().async { errors.drain(stderr.fileHandleForReading); readers.leave() }
        if let input {
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }
        }
        if exited.wait(timeout: .now() + 8) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                // This PID is our still-running direct child, never a caller-supplied process.
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 1)
            }
            throw GuardFailure.message("A guard system command timed out. Protection or restoration could not be confirmed.")
        }
        guard readers.wait(timeout: .now() + 1) == .success else { throw GuardFailure.message("A guard system command did not close its output pipes.") }
        return CommandResult(code: process.terminationStatus, output: try output.result(), error: try errors.result())
    }
}
