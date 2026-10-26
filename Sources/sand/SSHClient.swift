import Foundation

struct SSHClient {
    let processRunner: ProcessRunning
    let host: String
    let config: Config.SSH

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

    private var passwordEnvironment: [String: String] {
        ["SSHPASS": config.password]
    }

    func exec(command: String) async throws -> ProcessResult? {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try await processRunner.run(
            executable: "sshpass",
            arguments: ["-e", "ssh"]
                + Self.commonOptions
                + ["-p", String(config.port), "\(config.user)@\(host)", remote],
            environment: passwordEnvironment,
            wait: true
        )
    }

    func start(command: String) throws -> ProcessHandle {
        let escaped = command.replacingOccurrences(of: "'", with: "'\"'\"'")
        let remote = "/bin/bash -lc '\(escaped)'"
        return try processRunner.start(
            executable: "sshpass",
            arguments: ["-e", "ssh"]
                + Self.commonOptions
                + ["-p", String(config.port), "\(config.user)@\(host)", remote],
            environment: passwordEnvironment
        )
    }

    func copy(localPath: String, remotePath: String) async throws -> ProcessResult? {
        return try await processRunner.run(
            executable: "sshpass",
            arguments: ["-e", "scp"]
                + Self.commonOptions
                + ["-P", String(config.port), localPath, "\(config.user)@\(host):\(remotePath)"],
            environment: passwordEnvironment,
            wait: true
        )
    }

    func checkConnection() async throws {
        _ = try await exec(command: "true")
    }
}
