import Foundation
import Testing
@testable import ModAwake

struct AwakePolicyTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func offNeverHolds() {
        #expect(!AwakePolicy.shouldHold(mode: .off, manualUntil: nil, lastAgentActivity: now, now: now, grace: 60))
    }

    @Test func manualHoldsUntilDeadlineOrForever() {
        #expect(AwakePolicy.shouldHold(mode: .manual, manualUntil: nil, lastAgentActivity: nil, now: now, grace: 60))
        #expect(AwakePolicy.shouldHold(mode: .manual, manualUntil: now + 1, lastAgentActivity: nil, now: now, grace: 60))
        #expect(!AwakePolicy.shouldHold(mode: .manual, manualUntil: now, lastAgentActivity: nil, now: now, grace: 60))
    }

    @Test func autoHoldsDuringGraceOnly() {
        #expect(!AwakePolicy.shouldHold(mode: .auto, manualUntil: nil, lastAgentActivity: nil, now: now, grace: 60))
        #expect(AwakePolicy.shouldHold(mode: .auto, manualUntil: nil, lastAgentActivity: now - 59, now: now, grace: 60))
        #expect(!AwakePolicy.shouldHold(mode: .auto, manualUntil: nil, lastAgentActivity: now - 60, now: now, grace: 60))
    }

    @Test func labels() {
        #expect(AwakeModule.durationLabel(0) == "무제한")
        #expect(AwakeModule.durationLabel(3 * 3600) == "3시간")
        #expect(AwakeModule.remainingLabel(161 * 60) == "2시간 41분")
        #expect(AwakeModule.remainingLabel(30) == "1분")
    }
}

@Suite(.serialized)
struct AgentDetectorTests {
    let home: URL
    let fileManager = FileManager.default

    init() throws {
        home = fileManager.temporaryDirectory.appendingPathComponent("ModAwakeTests-\(UUID().uuidString)")
        try fileManager.createDirectory(at: home, withIntermediateDirectories: true)
    }

    func write(_ relativePath: String, _ contents: String, modified: Date = Date()) throws {
        let url = home.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    func detector(_ sources: Set<AgentDetector.Source> = Set(AgentDetector.Source.allCases), permission: Bool = true) -> AgentDetector {
        AgentDetector(home: home, sources: sources, countsPermissionWait: permission)
    }

    func writePaseoPID(alive: Bool) throws {
        let pid = alive ? ProcessInfo.processInfo.processIdentifier : 999_999
        try write(".paseo/paseo.pid", #"{"pid": \#(pid), "listen": "127.0.0.1:6767"}"#)
    }

    func writePaseoAgent(_ name: String, status: String, attention: String? = nil) throws {
        let reason = attention.map { #""\#($0)""# } ?? "null"
        try write(
            ".paseo/agents/project/\(name).json",
            #"{"provider": "claude", "lastStatus": "\#(status)", "requiresAttention": \#(attention != nil), "attentionReason": \#(reason)}"#
        )
    }

    @Test func freshTranscriptCountsStaleDoesNot() throws {
        try write(".claude/projects/p/a.jsonl", "{}", modified: Date().addingTimeInterval(-300))
        #expect(detector().detect().isEmpty)

        try write(".codex/sessions/2026/10/19/rollout-1.jsonl", "{}")
        #expect(detector().detect().map(\.name) == ["Codex"])
        #expect(detector([.claude]).detect().isEmpty)
    }

    @Test func paseoRunningAgentCountsOnlyWhileDaemonAlive() throws {
        try writePaseoAgent("a1", status: "running")
        try writePaseoPID(alive: false)
        #expect(detector().detect().isEmpty)

        try writePaseoPID(alive: true)
        #expect(detector().detect().map(\.name) == ["Claude (Paseo)"])
    }

    @Test func paseoAttentionCountsOnlyForPermission() throws {
        try writePaseoPID(alive: true)
        try writePaseoAgent("done", status: "idle", attention: "finished")
        try writePaseoAgent("input", status: "idle", attention: "needs_input")
        #expect(detector().detect().isEmpty)

        try writePaseoAgent("perm", status: "idle", attention: "permission")
        #expect(detector().detect().map(\.name) == ["Claude (Paseo)"])
        #expect(detector(permission: false).detect().isEmpty)
    }

    @Test func paseoSupersedesTranscriptForSameProvider() throws {
        try writePaseoPID(alive: true)
        try writePaseoAgent("a1", status: "running")
        try write(".claude/projects/p/a.jsonl", "{}")
        #expect(detector().detect().map(\.name) == ["Claude (Paseo)"])
    }
}
