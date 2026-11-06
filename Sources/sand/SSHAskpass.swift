import Foundation

enum SSHAskpass {
    static let passwordVariable = "SAND_SSH_PASSWORD"
    static let script = "#!/bin/sh\nprintf '%s\\n' \"$\(passwordVariable)\"\n"

    static var defaultPath: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sand-\(getuid())", isDirectory: true)
            .appendingPathComponent("ssh-askpass")
            .path
    }

    static func ensureScript(at path: String) throws {
        let fileManager = FileManager.default
        if fileManager.isExecutableFile(atPath: path),
           let existing = fileManager.contents(atPath: path),
           existing == Data(script.utf8) {
            return
        }
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try Data(script.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
    }

    static func environment(password: String, path: String) -> [String: String] {
        [
            "SSH_ASKPASS": path,
            "SSH_ASKPASS_REQUIRE": "force",
            passwordVariable: password
        ]
    }
}
