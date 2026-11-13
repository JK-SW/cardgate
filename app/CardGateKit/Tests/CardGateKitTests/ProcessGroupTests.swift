import CardGateKit
import Foundation
import Testing

@Suite(.serialized)
struct ProcessGroupTests {
    /// Runs perl (part of macOS) and waits until it printed the pid of its child.
    static func start(_ script: String) throws -> (process: Process, child: pid_t?) {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/perl")
        process.arguments = ["-e", script]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data("\n".utf8) {
            line.append(byte)
        }
        return (process, String(bytes: line, encoding: .utf8).flatMap { pid_t($0) })
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    static func waitUntilGone(_ pid: pid_t) async {
        for _ in 0..<100 where isAlive(pid) {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    /// A hanging card check with a process the driver started: both end.
    @Test func killsTheWholeGroup() async throws {
        let (process, child) = try Self.start(
            #"setpgrp(0, 0); my $c = fork(); if ($c == 0) { sleep 30; exit 0 } $| = 1; print "$c\n"; sleep 30;"#)
        let helper = try #require(child)
        #expect(Self.isAlive(helper))
        ProcessGroup.kill(leader: process.processIdentifier)
        process.waitUntilExit()
        await Self.waitUntilGone(helper)
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(!Self.isAlive(helper))
    }

    /// A check that hung before it started its own group is still stopped.
    @Test func killsAProcessWithoutItsOwnGroup() throws {
        let (process, _) = try Self.start(#"$| = 1; print "0\n"; sleep 30;"#)
        ProcessGroup.kill(leader: process.processIdentifier)
        process.waitUntilExit()
        #expect(process.terminationReason == .uncaughtSignal)
    }
}
