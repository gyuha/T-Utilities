import Foundation

// Pure calculations and formatting for the Stats module (no system calls, so they are unit-testable).
// Design reference only: exelban/stats (MIT) — https://github.com/exelban/stats

/// Cumulative system-wide CPU ticks (`host_statistics` HOST_CPU_LOAD_INFO).
struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user + system + nice }
    var total: UInt64 { busy + idle }

    /// System CPU usage in percent (0–100) between two samples. `nil` when no ticks elapsed.
    static func usage(from previous: CPUTicks, to current: CPUTicks) -> Double? {
        guard current.total > previous.total, current.busy >= previous.busy else { return nil }
        return Double(current.busy - previous.busy) / Double(current.total - previous.total) * 100
    }
}

/// Mach absolute time → nanoseconds. `ri_user_time`/`ri_system_time` are mach units (125/3 ns on Apple Silicon).
struct Timebase: Equatable, Sendable {
    var numer: UInt32
    var denom: UInt32

    func nanoseconds(_ ticks: UInt64) -> UInt64 {
        // Split to avoid overflow of ticks * numer for long-running processes.
        let whole = ticks / UInt64(denom)
        let rest = ticks % UInt64(denom)
        return whole * UInt64(numer) + rest * UInt64(numer) / UInt64(denom)
    }
}

/// One process at one instant.
struct ProcessSample: Equatable, Sendable {
    var pid: Int32
    var name: String
    /// `ri_phys_footprint` — what Activity Monitor shows as "Memory".
    var footprint: UInt64
    /// `ri_user_time + ri_system_time`, mach units.
    var cpuTicks: UInt64
}

struct ProcessUsage: Equatable, Sendable, Identifiable {
    var pid: Int32
    var name: String
    /// Percent of one core (can exceed 100 for multithreaded processes, like Activity Monitor).
    var cpuPercent: Double
    var footprint: UInt64
    var id: Int32 { pid }
}

/// Cumulative bytes of one network interface (`if_data` `ifi_ibytes`/`ifi_obytes`, 32-bit on macOS).
struct NetworkCounters: Equatable, Sendable {
    var received: UInt64
    var sent: UInt64
}

/// Bytes per second.
struct NetworkRate: Equatable, Sendable {
    var down: Double
    var up: Double
}

enum StatsMath {
    /// Counters in `if_data` are 32-bit and wrap at 4 GiB.
    static let counterModulus: UInt64 = 1 << 32
    /// A decrease is treated as a wrap only if it implies at most this many bytes since the last sample;
    /// anything larger is an interface reset (down/up), which counts as 0.
    static let maxWrapDelta: UInt64 = 1 << 30

    /// Bytes transferred between two readings of a 32-bit counter, tolerating wrap-around and resets.
    static func counterDelta(from previous: UInt64, to current: UInt64) -> UInt64 {
        if current >= previous { return current - previous }
        guard previous <= counterModulus else { return 0 }
        let wrapped = counterModulus - previous + current
        return wrapped <= maxWrapDelta ? wrapped : 0
    }

    /// Total rate over all interfaces present in both samples. `nil` when no time elapsed or nothing was measured.
    static func networkRate(
        previous: [String: NetworkCounters], current: [String: NetworkCounters], seconds: Double
    ) -> NetworkRate? {
        guard seconds > 0, !current.isEmpty else { return nil }
        var down: UInt64 = 0
        var up: UInt64 = 0
        for (name, now) in current {
            guard let old = previous[name] else { continue }
            down += counterDelta(from: old.received, to: now.received)
            up += counterDelta(from: old.sent, to: now.sent)
        }
        return NetworkRate(down: Double(down) / seconds, up: Double(up) / seconds)
    }

    /// Used share of a capacity, 0...1. 0 when the total is unknown.
    static func fraction(used: UInt64, total: UInt64) -> Double {
        total > 0 ? min(Double(used) / Double(total), 1) : 0
    }

    /// Per-process CPU% from two samples taken `wallNanoseconds` apart. Processes that did not exist in
    /// `previous` (or whose time went backwards, i.e. a recycled pid) get 0%.
    static func processUsage(
        previous: [Int32: ProcessSample], current: [ProcessSample], wallNanoseconds: UInt64, timebase: Timebase
    ) -> [ProcessUsage] {
        current.map { sample in
            var percent = 0.0
            if wallNanoseconds > 0, let old = previous[sample.pid], sample.cpuTicks >= old.cpuTicks {
                let cpuNs = timebase.nanoseconds(sample.cpuTicks - old.cpuTicks)
                percent = Double(cpuNs) / Double(wallNanoseconds) * 100
            }
            return ProcessUsage(pid: sample.pid, name: sample.name, cpuPercent: percent, footprint: sample.footprint)
        }
    }

    static func topByCPU(_ usages: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        Array(usages.sorted { ($0.cpuPercent, $1.pid) > ($1.cpuPercent, $0.pid) }.prefix(limit))
    }

    static func topByMemory(_ usages: [ProcessUsage], limit: Int) -> [ProcessUsage] {
        Array(usages.sorted { ($0.footprint, $1.pid) > ($1.footprint, $0.pid) }.prefix(limit))
    }

    // MARK: - Formatting

    /// "36", "18.2" (trailing ".0" dropped).
    static func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return gb >= 100 ? String(format: "%.0f", gb) : String(format: "%.1f", gb).replacingOccurrences(of: ".0", with: "")
    }

    /// "18.2/36 GB"
    static func memoryText(used: UInt64, total: UInt64) -> String {
        "\(formatGB(used))/\(formatGB(total)) GB"
    }

    /// Process memory: MB below 1 GB, otherwise GB with one decimal.
    static func formatProcessMemory(_ bytes: UInt64) -> String {
        bytes >= 1_073_741_824 ? String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
            : String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    static func formatPercent(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : String(format: "%.0f%%", value)
    }

    /// "0 B/s", "340 KB/s", "1.2 MB/s" (1024-based, like Activity Monitor).
    static func formatRate(_ bytesPerSecond: Double) -> String {
        let kb = bytesPerSecond / 1024
        if kb < 1 { return String(format: "%.0f B/s", bytesPerSecond) }
        if kb < 1000 { return String(format: "%.0f KB/s", kb) }
        return String(format: "%.1f MB/s", kb / 1024)
    }

    /// "↓ 1.2 MB/s ↑ 340 KB/s"
    static func networkText(_ rate: NetworkRate) -> String {
        "↓ \(formatRate(rate.down)) ↑ \(formatRate(rate.up))"
    }

    /// Popover row text, e.g. "CPU 12% · 메모리 18.2/36 GB". CPU shows "…" until the second sample is in.
    static func summaryText(cpu: Double?, memory: (used: UInt64, total: UInt64)?) -> String {
        let cpuText = cpu.map { "CPU \(String(format: "%.0f", $0))%" } ?? "CPU …"
        guard let memory else { return cpuText }
        return "\(cpuText) · 메모리 \(memoryText(used: memory.used, total: memory.total))"
    }
}
