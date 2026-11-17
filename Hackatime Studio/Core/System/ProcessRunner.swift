import Foundation

nonisolated struct ProcessResult: Sendable {
    var status: Int32
    var stdout: String
    var stderr: String
    var timedOut: Bool
    var succeeded: Bool { status == 0 && !timedOut }
}

nonisolated enum ProcessRunnerError: LocalizedError {
    case launchFailed(String)
    var errorDescription: String? {
        switch self {
        case .launchFailed(let why): "Could not start the process: \(why)"
        }
    }
}

/// Runs short-lived helper processes (VS Code CLI, wakatime-cli --version, login shell probes)
/// off the main actor, with a timeout.
nonisolated enum ProcessRunner {

    @concurrent
    static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil,
                    timeout: TimeInterval = 30) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice

        do { try process.run() } catch { throw ProcessRunnerError.launchFailed(error.localizedDescription) }

        // Read pipes concurrently so a chatty process can't fill the buffer and deadlock.
        async let stdoutData = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }.value
        async let stderrData = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }.value

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() > deadline {
                timedOut = true
                process.terminate()
                break
            }
            try? await Task.sleep(for: .milliseconds(40))
        }
        process.waitUntilExit()
        let o = await stdoutData, e = await stderrData
        return ProcessResult(status: process.terminationStatus,
                             stdout: String(decoding: o, as: UTF8.self),
                             stderr: String(decoding: e, as: UTF8.self),
                             timedOut: timedOut)
    }
}
