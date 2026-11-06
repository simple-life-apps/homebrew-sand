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
    private var askpassPath: String!

    override func setUpWithError() throws {
        askpassPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("sand-tests-\(UUID().uuidString)")
            .appendingPathComponent("ssh-askpass")
            .path
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: (askpassPath as NSString).deletingLastPathComponent)
    }

    private func makeClient(_ runner: SSHProcessRunner, password: String, port: Int) -> SSHClient {
        SSHClient(
            processRunner: runner,
            host: "10.0.0.1",
            config: .init(user: "admin", password: password, port: port),
            askpassPath: askpassPath
        )
    }

    func testStartBuildsSSHCommand() async throws {
        let runner = SSHProcessRunner()
        let ssh = makeClient(runner, password: "pw", port: 2222)
        let handle = try ssh.start(command: "echo hi")
        _ = try await handle.waitAsync()
        let expected = SSHProcessRunner.Call(
            executable: "ssh",
            arguments: [
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
            environment: [
                "SSH_ASKPASS": askpassPath,
                "SSH_ASKPASS_REQUIRE": "force",
                "SAND_SSH_PASSWORD": "pw"
            ]
        )
        XCTAssertEqual(runner.startCalls.first, expected)
    }

    func testPasswordStaysOffCommandLine() async throws {
        let runner = SSHProcessRunner()
        let ssh = makeClient(runner, password: "hunter2", port: 22)
        _ = try await ssh.exec(command: "true")
        _ = try await ssh.copy(localPath: "/tmp/a", remotePath: "b")
        _ = try ssh.start(command: "true")
        let calls = runner.runCalls + runner.startCalls
        XCTAssertEqual(calls.count, 3)
        for call in calls {
            XCTAssertFalse(call.arguments.contains("hunter2"))
            XCTAssertEqual(call.environment["SAND_SSH_PASSWORD"], "hunter2")
            XCTAssertEqual(call.environment["SSH_ASKPASS"], askpassPath)
        }
        XCTAssertEqual(calls.map(\.executable), ["ssh", "scp", "ssh"])
    }

    func testAskpassScriptPrintsPasswordFromEnvironment() async throws {
        let runner = SSHProcessRunner()
        _ = try await makeClient(runner, password: "unused", port: 22).exec(command: "true")
        let attributes = try FileManager.default.attributesOfItem(atPath: askpassPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: askpassPath)
        process.arguments = ["admin@10.0.0.1's password: "]
        process.environment = ["SAND_SSH_PASSWORD": "p@ss 'w\"ord $HOME"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output, "p@ss 'w\"ord $HOME\n")
    }

    func testAskpassScriptIsRecreatedWhenRemoved() async throws {
        let runner = SSHProcessRunner()
        let ssh = makeClient(runner, password: "pw", port: 22)
        _ = try await ssh.exec(command: "true")
        try FileManager.default.removeItem(atPath: askpassPath)
        _ = try await ssh.exec(command: "true")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: askpassPath))
    }
}
