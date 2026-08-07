import Foundation
import Darwin

// MARK: - Network traffic

struct InterfaceTraffic: Identifiable {
    let name: String
    let received: UInt64
    let sent: UInt64

    var id: String { name }
}

struct NetworkTrafficSnapshot {
    let received: UInt64
    let sent: UInt64
    let interfaces: [InterfaceTraffic]
}

enum NetworkTraffic {

    // sysctl constants (CTL_NET, PF_ROUTE, NET_RT_IFLIST2, RTM_IFINFO2)
    // are C macros and not imported into Swift, so define them here.
    private static let ctlNet: Int32 = 4
    private static let pfRoute: Int32 = 17
    private static let netRTIFList2: Int32 = 6
    private static let rtmIfinfo2: UInt8 = 0x12

    /// Reads per-interface byte counters via NET_RT_IFLIST2.
    /// Uses 64-bit counters (if_data64) to avoid the 32-bit overflow
    /// that a plain if_data/getifaddrs read would have.
    static func snapshot() -> NetworkTrafficSnapshot? {
        var mib: [Int32] = [ctlNet, pfRoute, 0, 0, netRTIFList2, 0]
        var len = 0
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, u_int(mib.count), &buf, &len, nil, 0) == 0 else { return nil }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var interfaces: [InterfaceTraffic] = []

        var offset = 0
        let headerSize = MemoryLayout<if_msghdr2>.size
        while offset + headerSize <= buf.count {
            let msg = buf.withUnsafeBytes { raw -> if_msghdr2? in
                guard offset + headerSize <= raw.count else { return nil }
                return raw.load(fromByteOffset: offset, as: if_msghdr2.self)
            }
            guard let msg = msg else { break }
            let msglen = Int(msg.ifm_msglen)
            guard msglen >= headerSize, offset + msglen <= buf.count else { break }

            if msg.ifm_type == rtmIfinfo2 {
                let rx = msg.ifm_data.ifi_ibytes
                let tx = msg.ifm_data.ifi_obytes
                received &+= rx
                sent &+= tx
                let name = buf.withUnsafeBytes { raw -> String in
                    let base = raw.baseAddress!.assumingMemoryBound(to: CChar.self)
                        .advanced(by: offset + headerSize)
                    return String(cString: base)
                }
                interfaces.append(InterfaceTraffic(name: name, received: rx, sent: tx))
            }

            offset += msglen
        }

        return NetworkTrafficSnapshot(received: received,
                                      sent: sent,
                                      interfaces: interfaces.sorted { $0.name < $1.name })
    }
}
