import Foundation

/// Apps launched from Finder/Dock don't inherit variables exported in `~/.zshrc`, but VS Code
/// resolves the login-shell environment at startup — so the extension may see `WAKATIME_HOME`
/// while Studio would not. We resolve the same variables the same way VS Code does.
///
/// Only *names we need* are read, and the API-key variable is checked for presence only — its
/// value never enters Studio's process.
nonisolated struct ShellEnvironment: Sendable, Equatable {
    var wakatimeHome: String?
    var xdgConfigHome: String?
    var hasAPIKeyVariable: Bool
    var hasAPIURLVariable: Bool
    var resolvedFromShell: Bool

    static let processOnly = ShellEnvironment(
        wakatimeHome: nonEmpty(ProcessInfo.processInfo.environment["WAKATIME_HOME"]),
        xdgConfigHome: nonEmpty(ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]),
        hasAPIKeyVariable: nonEmpty(ProcessInfo.processInfo.environment["WAKATIME_API_KEY"]) != nil,
        hasAPIURLVariable: nonEmpty(ProcessInfo.processInfo.environment["WAKATIME_API_URL"]) != nil,
        resolvedFromShell: false)

    @concurrent
    static func resolve() async -> ShellEnvironment {
        var env = processOnly
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap(nonEmpty) ?? "/bin/zsh"
        let marker = "__HACKATIME_STUDIO__"
        let script = """
        printf '\(marker)%s\\n' "${WAKATIME_HOME:-}"; \
        printf '\(marker)%s\\n' "${XDG_CONFIG_HOME:-}"; \
        if [ -n "${WAKATIME_API_KEY:-}" ]; then printf '\(marker)1\\n'; else printf '\(marker)0\\n'; fi; \
        if [ -n "${WAKATIME_API_URL:-}" ]; then printf '\(marker)1\\n'; else printf '\(marker)0\\n'; fi
        """
        guard let result = try? await ProcessRunner.run(URL(fileURLWithPath: shell),
                                                        arguments: ["-ilc", script], timeout: 6),
              result.succeeded else { return env }
        let values = result.stdout.components(separatedBy: "\n")
            .filter { $0.hasPrefix(marker) }
            .map { String($0.dropFirst(marker.count)) }
        guard values.count == 4 else { return env }
        env.wakatimeHome = env.wakatimeHome ?? nonEmpty(values[0])
        env.xdgConfigHome = env.xdgConfigHome ?? nonEmpty(values[1])
        env.hasAPIKeyVariable = env.hasAPIKeyVariable || values[2] == "1"
        env.hasAPIURLVariable = env.hasAPIURLVariable || values[3] == "1"
        env.resolvedFromShell = true
        return env
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }
}
