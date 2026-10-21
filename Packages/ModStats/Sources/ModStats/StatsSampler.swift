import Darwin
import Foundation

/// Reads system and per-process counters through public Darwin/Mach APIs. Stateless and thread-safe;
/// listing every process takes a few tens of ms, so callers run it off the main thread.
enum StatsSampler {
    struct Snapshot: Sendable {
        var ticks: CPUTicks
        var processes: [ProcessSample]
        var memoryUsed: UInt64
        var memoryTotal: UInt64
        /// `CLOCK_UPTIME_RAW` at sampling time (same clock family as the mach times; excludes sleep).
        var wallNanoseconds: UInt64
    }

    static func takeSnapshot() -> Snapshot {
        let wall = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let memory = readMemory()
        return Snapshot(
            ticks: readCPUTicks() ?? CPUTicks(user: 0, system: 0, idle: 0, nice: 0),
            processes: readProcesses(),
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            wallNanoseconds: wall
        )
    }

    static let timebase: Timebase = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Timebase(numer: info.numer, denom: max(info.denom, 1))
    }()

    static func readCPUTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        // cpu_ticks order: USER, SYSTEM, IDLE, NICE
        return CPUTicks(
            user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3)
        )
    }

    /// "Memory Used" as Activity Monitor computes it: app memory (internal − purgeable) + wired + compressed.
    static func readMemory() -> (used: UInt64, total: UInt64) {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total) }
        let internalPages = UInt64(stats.internal_page_count)
        let app = internalPages &- min(UInt64(stats.purgeable_count), internalPages)
        let pages = app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return (min(pages * UInt64(pageSize), total), total)
    }

    /// Every process whose rusage we may read. Other users' / root processes fail and are skipped silently.
    static func readProcesses() -> [ProcessSample] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 32)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }

        var nameBuffer = [CChar](repeating: 0, count: 64)
        var result: [ProcessSample] = []
        let count = Int(filled) / MemoryLayout<pid_t>.size
        result.reserveCapacity(count)
        for pid in pids.prefix(count) where pid > 0 {
            var info = rusage_info_current()
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, $0)
                }
            }
            guard status == 0 else { continue }
            let length = proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = length > 0 ? String(decoding: nameBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : "pid \(pid)"
            result.append(ProcessSample(
                pid: pid, name: name, footprint: info.ri_phys_footprint,
                cpuTicks: info.ri_user_time &+ info.ri_system_time
            ))
        }
        return result
    }
}
