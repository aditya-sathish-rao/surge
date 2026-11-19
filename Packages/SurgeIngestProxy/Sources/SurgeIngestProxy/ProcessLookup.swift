import Darwin
import Foundation

public struct ProcessFacts: Sendable, Equatable {
    public let processID: pid_t
    public let parentProcessID: pid_t
    public let workingDirectory: String?

    public init(processID: pid_t, parentProcessID: pid_t, workingDirectory: String?) {
        self.processID = processID
        self.parentProcessID = parentProcessID
        self.workingDirectory = workingDirectory
    }
}

/// Boundary around libproc so the proxy logic can be tested without touching the process table.
public protocol ProcessLookup: Sendable {
    /// The process that owns the local end of a loopback connection.
    func clientProcessID(sourcePort: UInt16, destinationPort: UInt16) -> pid_t?

    func facts(forPID pid: pid_t) -> ProcessFacts?
}

public struct LibprocProcessLookup: ProcessLookup {
    public init() {}

    public func clientProcessID(sourcePort: UInt16, destinationPort: UInt16) -> pid_t? {
        guard sourcePort > 0 else { return nil }
        for pid in Self.allProcessIDs() where pid > 0 {
            for descriptor in Self.socketDescriptors(for: pid) {
                guard let ports = Self.tcpPorts(for: pid, descriptor: descriptor) else { continue }
                if ports.source == sourcePort && ports.destination == destinationPort {
                    return pid
                }
            }
        }
        return nil
    }

    public func facts(forPID pid: pid_t) -> ProcessFacts? {
        guard pid > 0 else { return nil }
        return ProcessFacts(
            processID: pid,
            parentProcessID: Self.parentProcessID(of: pid) ?? 0,
            workingDirectory: Self.workingDirectory(of: pid)
        )
    }

    private static func allProcessIDs() -> [pid_t] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 32)
        let byteCount = Int32(pids.count * MemoryLayout<pid_t>.size)
        let actual = proc_listallpids(&pids, byteCount)
        guard actual > 0 else { return [] }
        return Array(pids.prefix(Int(actual)))
    }

    private static func socketDescriptors(for pid: pid_t) -> [proc_fdinfo] {
        let estimated = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard estimated > 0 else { return [] }
        let capacity = Int(estimated) / MemoryLayout<proc_fdinfo>.size + 16
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let byteCount = Int32(capacity * MemoryLayout<proc_fdinfo>.size)
        let actual = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, byteCount)
        guard actual > 0 else { return [] }
        let count = Int(actual) / MemoryLayout<proc_fdinfo>.size
        return descriptors.prefix(count).filter { $0.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) }
    }

    private static func tcpPorts(
        for pid: pid_t,
        descriptor: proc_fdinfo
    ) -> (source: UInt16, destination: UInt16)? {
        var info = socket_fdinfo()
        let byteCount = Int32(MemoryLayout<socket_fdinfo>.size)
        let result = proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, byteCount)
        guard result == byteCount, info.psi.soi_kind == Int32(SOCKINFO_TCP) else { return nil }
        let tcp = info.psi.soi_proto.pri_tcp.tcpsi_ini
        let source = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.insi_lport))
        let destination = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.insi_fport))
        return (source, destination)
    }

    private static func parentProcessID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let byteCount = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, byteCount)
        guard result == byteCount else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let byteCount = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, byteCount)
        guard result == byteCount else { return nil }
        return withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(bytes: bytes, encoding: .utf8)
        }
    }
}
