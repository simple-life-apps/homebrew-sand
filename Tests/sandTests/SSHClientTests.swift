import XCTest
@testable import sand

final class SSHProcessRunner: ProcessRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let wait: Bool
        var environment: [String: String] = [:]
    }

    var runCalls: [Call] = []
    var startCalls: [Call] = []

    func run(executable: String, arguments: [String], environment: [String: String], wait: Bool) async throws -> ProcessResult? {
        runCalls.append(Call(executable: executable, arguments: arguments, wait: wait, environment: environment))
        return ProcessResult(stdout: "", stderr: "", exitCode: 0)
    }

    func start(executable: String, arguments: [String], environment: [String: String]) throws -> ProcessHandle {
        startCalls.append(Call(executable: executable, arguments: arguments, wait: false, environment: environment))
        return ProcessHandle(
            waitAsync: { ProcessResult(stdout: "", stderr: "", exitCode: 0) },
            terminate: {}
        )
    }
}

final class SSHClientTests: XCTestCase {
    func testStartBuildsSSHCommand() async throws {
        let runner = SSHProcessRunner()
        let ssh = SSHClient(
            processRunner: runner,
            host: "10.0.0.1",
            config: .init(user: "admin", password: "pw", port: 2222)
        )
        let handle = try ssh.start(command: "echo hi")
        _ = try await handle.waitAsync()
        let expected = SSHProcessRunner.Call(
            executable: "sshpass",
            arguments: [
                "-e",
                "ssh",
                "-o", "PreferredAuthentications=password",
                "-o", "PubkeyAuthentication=no",
                "-o", "IdentitiesOnly=yes",
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=/dev/null",
                "-o", "LogLevel=ERROR",
                "-o", "ConnectTimeout=10",
                "-o", "ServerAliveInterval=30",
                "-o", "ServerAliveCountMax=6",
                "-p", "2222",
                "admin@10.0.0.1",
                "/bin/bash -lc 'echo hi'"
            ],
            wait: false,
            environment: ["SSHPASS": "pw"]
        )
        XCTAssertEqual(runner.startCalls.first, expected)
    }

    func testPasswordStaysOffCommandLine() async throws {
        let runner = SSHProcessRunner()
        let ssh = SSHClient(
            processRunner: runner,
            host: "10.0.0.1",
            config: .init(user: "admin", password: "hunter2", port: 22)
        )
        _ = try await ssh.exec(command: "true")
        _ = try await ssh.copy(localPath: "/tmp/a", remotePath: "b")
        _ = try ssh.start(command: "true")
        let calls = runner.runCalls + runner.startCalls
        XCTAssertEqual(calls.count, 3)
        for call in calls {
            XCTAssertFalse(call.arguments.contains("hunter2"))
            XCTAssertEqual(call.environment, ["SSHPASS": "hunter2"])
        }
    }
}
