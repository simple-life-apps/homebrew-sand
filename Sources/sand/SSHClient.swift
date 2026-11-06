import Foundation

struct SSHClient {
    let processRunner: ProcessRunning
    let host: String
    let config: Config.SSH
    var askpassPath: String = SSHAskpass.defaultPath

    private static let commonOptions: [String] = [
        "-o", "PreferredAuthentications=password",
        "-o", "PubkeyAuthentication=no",
        "-o", "IdentitiesOnly=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-o", "ConnectTimeout=10",
        "-o", "ServerAliveInterval=30",
        "-o", "ServerAliveCountMax=6"
    ]

    private func passwordEnvironment() throws -> [String: String] {
        try SSHAskpass.ensureScript(at: askpassPath)
        return SSHAskpass.environment(password: config.password, path: askpassPath)
    }

    func exec(command: String) async throws -> ProcessResult? {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try await processRunner.run(
            executable: "ssh",
            arguments: Self.commonOptions
                + ["-p", String(config.port), "\(config.user)@\(host)", remote],
            environment: try passwordEnvironment(),
            wait: true
        )
    }

    func start(command: String) throws -> ProcessHandle {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try processRunner.start(
            executable: "ssh",
            arguments: Self.commonOptions
                + ["-p", String(config.port), "\(config.user)@\(host)", remote],
            environment: try passwordEnvironment()
        )
    }

    func copy(localPath: String, remotePath: String) async throws -> ProcessResult? {
        return try await processRunner.run(
            executable: "scp",
            arguments: Self.commonOptions
                + ["-P", String(config.port), localPath, "\(config.user)@\(host):\(remotePath)"],
            environment: try passwordEnvironment(),
            wait: true
        )
    }

    func checkConnection() async throws {
        _ = try await exec(command: "true")
    }
}
