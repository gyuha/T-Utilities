import Foundation
import Testing
@testable import ModStats

struct StatsMathTests {
    @Test func systemCPUFromTickDeltas() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let b = CPUTicks(user: 160, system: 70, idle: 920, nice: 0)
        // busy +80, idle +70 -> 80/150
        #expect(abs(CPUTicks.usage(from: a, to: b)! - 53.333) < 0.01)
        #expect(CPUTicks.usage(from: b, to: b) == nil)
    }

    @Test func timebaseConvertsAppleSiliconUnits() {
        let tb = Timebase(numer: 125, denom: 3)
        #expect(tb.nanoseconds(24_000_000) == 1_000_000_000)
        #expect(Timebase(numer: 1, denom: 1).nanoseconds(5) == 5)
        #expect(tb.nanoseconds(UInt64.max / 1000) > 0) // no overflow trap
    }

    @Test func processCPUUsesTimebaseAndWallTime() {
        let tb = Timebase(numer: 125, denom: 3)
        let before = [ProcessSample(pid: 1, name: "a", footprint: 0, cpuTicks: 1_000)]
        // +12_000_000 ticks = 500 ms CPU over 1 s wall = 50%
        let now = [
            ProcessSample(pid: 1, name: "a", footprint: 10, cpuTicks: 12_001_000),
            ProcessSample(pid: 2, name: "new", footprint: 20, cpuTicks: 99_999),
        ]
        let usages = StatsMath.processUsage(
            previous: Dictionary(uniqueKeysWithValues: before.map { ($0.pid, $0) }),
            current: now, wallNanoseconds: 1_000_000_000, timebase: tb
        )
        #expect(abs(usages[0].cpuPercent - 50) < 0.001)
        #expect(usages[1].cpuPercent == 0) // not in previous sample
    }

    @Test func recycledPidDoesNotUnderflow() {
        let prev: [Int32: ProcessSample] = [7:ProcessSample(pid: 7, name: "old", footprint: 0, cpuTicks: 500)]
        let usages = StatsMath.processUsage(
            previous: prev, current: [ProcessSample(pid: 7, name: "new", footprint: 0, cpuTicks: 10)],
            wallNanoseconds: 1_000_000_000, timebase: Timebase(numer: 1, denom: 1)
        )
        #expect(usages[0].cpuPercent == 0)
    }

    @Test func topNSorting() {
        let usages = (1...10).map {
            ProcessUsage(pid: Int32($0), name: "p\($0)", cpuPercent: Double($0), footprint: UInt64(11 - $0) * 1000)
        }
        #expect(StatsMath.topByCPU(usages, limit: 3).map(\.pid) == [10, 9, 8])
        #expect(StatsMath.topByMemory(usages, limit: 3).map(\.pid) == [1, 2, 3])
        #expect(StatsMath.topByCPU(usages, limit: 99).count == 10)
    }

    @Test func formatting() {
        #expect(StatsMath.memoryText(used: 19_551_000_000, total: 38_654_705_664) == "18.2/36 GB")
        #expect(StatsMath.formatProcessMemory(512 * 1_048_576) == "512 MB")
        #expect(StatsMath.formatProcessMemory(3 * 1_073_741_824) == "3.0 GB")
        #expect(StatsMath.formatPercent(4.26) == "4.3%")
        #expect(StatsMath.formatPercent(123.4) == "123%")
        #expect(StatsMath.summaryText(cpu: 12.3, memory: (19_551_000_000, 38_654_705_664)) == "CPU 12% · 메모리 18.2/36 GB")
        #expect(StatsMath.summaryText(cpu: nil, memory: nil) == "CPU …")
    }
}

/// Reads this Mac's real counters.
struct LiveSampleTests {
    @Test func liveSnapshotIsSane() async throws {
        let start = ContinuousClock.now
        let first = StatsSampler.takeSnapshot()
        print("STATS sample: \(ContinuousClock.now - start), processes: \(first.processes.count)")
        #expect(first.processes.count > 10)
        #expect(first.processes.contains { $0.pid == getpid() })
        #expect(first.memoryTotal >= 8 * 1_073_741_824)
        #expect(first.memoryUsed > 0 && first.memoryUsed <= first.memoryTotal)

        // Burn some CPU in this process so the two-sample math has something to see.
        let end = Date().addingTimeInterval(0.3)
        while Date() < end {}
        let second = StatsSampler.takeSnapshot()
        let cpu = try #require(CPUTicks.usage(from: first.ticks, to: second.ticks))
        #expect(cpu >= 0 && cpu <= 100)
        let usages = StatsMath.processUsage(
            previous: Dictionary(first.processes.map { ($0.pid, $0) }, uniquingKeysWith: { $1 }),
            current: second.processes,
            wallNanoseconds: second.wallNanoseconds - first.wallNanoseconds, timebase: StatsSampler.timebase
        )
        let me = try #require(usages.first { $0.pid == getpid() })
        #expect(me.cpuPercent > 30 && me.cpuPercent < 1600)
    }
}
