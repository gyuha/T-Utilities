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
        #expect(StatsMath.formatRate(0) == "0 B/s")
        #expect(StatsMath.formatRate(340 * 1024) == "340 KB/s")
        #expect(StatsMath.formatRate(1.5 * 1_048_576) == "1.5 MB/s")
        #expect(StatsMath.networkText(NetworkRate(down: 1.5 * 1_048_576, up: 2048)) == "↓ 1.5 MB/s ↑ 2 KB/s")
    }

    @Test func counterDeltaHandlesWrapAndReset() {
        #expect(StatsMath.counterDelta(from: 100, to: 600) == 500)
        // 32-bit wrap: 4 GiB - 1000 -> 500 is 1500 bytes
        #expect(StatsMath.counterDelta(from: (1 << 32) - 1000, to: 500) == 1500)
        // Big drop that is not a plausible wrap = interface reset
        #expect(StatsMath.counterDelta(from: 2_000_000_000, to: 10) == 0)
    }

    @Test func networkRateSumsInterfacesAndSkipsNewOnes() {
        let previous = ["en0": NetworkCounters(received: 1000, sent: 500), "en1": NetworkCounters(received: 0, sent: 0)]
        let current = [
            "en0": NetworkCounters(received: 3000, sent: 700),
            "en1": NetworkCounters(received: 1000, sent: 1000),
            "utun3": NetworkCounters(received: 999_999, sent: 999_999), // appeared between samples
        ]
        let rate = StatsMath.networkRate(previous: previous, current: current, seconds: 2)
        #expect(rate == NetworkRate(down: 1500, up: 600))
        #expect(StatsMath.networkRate(previous: previous, current: current, seconds: 0) == nil)
        #expect(StatsMath.networkRate(previous: previous, current: [:], seconds: 2) == nil)
    }

    @Test func fractionIsClamped() {
        #expect(StatsMath.fraction(used: 50, total: 200) == 0.25)
        #expect(StatsMath.fraction(used: 300, total: 200) == 1)
        #expect(StatsMath.fraction(used: 1, total: 0) == 0)
    }
}

/// Reads this Mac's real counters.
struct LiveSampleTests {
    @Test func liveSnapshotIsSane() async throws {
        let start = ContinuousClock.now
        let first = StatsSampler.takeSnapshot(.init(processes: true, network: true, disk: true, gpu: true))
        print("STATS sample: \(ContinuousClock.now - start), processes: \(first.processes.count)")
        print("STATS disk: \(String(describing: first.disk)), net: \(first.network), gpu: \(String(describing: first.gpuPercent))")
        #expect(first.network.keys.contains("lo0") == false)
        let disk = try #require(first.disk)
        #expect(disk.total > 0 && disk.used <= disk.total)
        #expect(first.processes.count > 10)
        #expect(first.processes.contains { $0.pid == getpid() })
        #expect(first.memoryTotal >= 8 * 1_073_741_824)
        #expect(first.memoryUsed > 0 && first.memoryUsed <= first.memoryTotal)

        // Burn some CPU in this process so the two-sample math has something to see.
        let end = Date().addingTimeInterval(0.3)
        while Date() < end {}
        let second = StatsSampler.takeSnapshot(.init(processes: true))
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
