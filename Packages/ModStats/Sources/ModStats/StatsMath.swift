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

enum StatsMath {
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

    /// Popover row text, e.g. "CPU 12% · 메모리 18.2/36 GB". CPU shows "…" until the second sample is in.
    static func summaryText(cpu: Double?, memory: (used: UInt64, total: UInt64)?) -> String {
        let cpuText = cpu.map { "CPU \(String(format: "%.0f", $0))%" } ?? "CPU …"
        guard let memory else { return cpuText }
        return "\(cpuText) · 메모리 \(memoryText(used: memory.used, total: memory.total))"
    }
}
