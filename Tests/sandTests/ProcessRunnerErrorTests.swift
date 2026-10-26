import XCTest
@testable import sand

final class ProcessRunnerErrorTests: XCTestCase {
    func testDescriptionOmitsArguments() {
        let error: Error = ProcessRunnerError.failed(
            exitCode: 1,
            stdout: "out",
            stderr: "err",
            command: ["sshpass", "-p", "hunter2", "ssh", "config.sh --token SECRET"]
        )
        let text = String(describing: error)
        XCTAssertEqual(text, "sshpass failed with exit code 1; stdout: out; stderr: err")
        XCTAssertFalse(text.contains("hunter2"))
        XCTAssertFalse(text.contains("SECRET"))
    }
}
