import Foundation
import Darwin

/// Reads the iOS/macOS kernel ARP table (IPv4 neighbour cache) via
/// `sysctl(NET_RT_FLAGS)` to obtain the MAC address of every local-network
/// host we've recently communicated with. Pairing a MAC address with the
/// IEEE OUI vendor database lets us tell the user *which manufacturer*
/// made a device even when it refuses to respond to Bonjour / SSDP / HTTP
/// fingerprinting — e.g., "Apple Device" or "Amazon Device" instead of a
/// meaningless "Unknown Device" or "Smart TV / Media".
///
/// Requirements: `NSLocalNetworkUsageDescription` must be set in Info.plist
/// and the user must have granted Local Network access. Without that,
/// the ARP table returns empty on iOS 14+.
///
/// The app has already probed every host on the subnet before this runs,
/// so the ARP cache is populated.
enum MACAddressResolver {
    /// `RTF_LLINFO` from `<net/route.h>`. The symbol isn't bridged to
    /// Swift, so we hard-code the stable value. Used to ask the kernel
    /// for just the entries populated by link-layer resolution (ARP for
    /// IPv4, ND for IPv6).
    private static let rtfLLInfoFlag: Int32 = 0x400

    /// `sizeof(struct rt_msghdr)` on 64-bit Darwin. The C struct isn't
    /// exposed to Swift, but its size is stable across iOS 13+ / macOS
    /// versions. We skip the header and walk the sockaddrs that follow.
    /// Field layout (from `<net/route.h>`):
    ///   u_short rtm_msglen        @ 0
    ///   u_char  rtm_version       @ 2
    ///   u_char  rtm_type          @ 3
    ///   u_short rtm_index         @ 4
    ///   int     rtm_flags         @ 8   (2 bytes of alignment padding)
    ///   int     rtm_addrs         @ 12
    ///   pid_t   rtm_pid           @ 16
    ///   int     rtm_seq           @ 20
    ///   int     rtm_errno         @ 24
    ///   int     rtm_use           @ 28
    ///   u_int32 rtm_inits         @ 32
    ///   rt_metrics rtm_rmx[60]    @ 36..96
    private static let rtMsghdrSize = 92

    /// Returns a map of IPv4 string → lowercase colon-separated MAC address
    /// (e.g., `"192.168.1.42"` → `"3c:22:fb:1a:2b:3c"`). Entries with a
    /// zero MAC (incomplete ARP resolution) are omitted.
    static func readARPTable() -> [String: String] {
        var mib: [Int32] = [
            CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_FLAGS, rtfLLInfoFlag,
        ]
        var len: size_t = 0

        // First pass: ask the kernel how much buffer we'll need.
        guard sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) == 0, len > 0 else {
            return [:]
        }

        let buf = UnsafeMutableRawPointer.allocate(
            byteCount: len,
            alignment: MemoryLayout<UInt>.alignment
        )
        defer { buf.deallocate() }

        guard sysctl(&mib, u_int(mib.count), buf, &len, nil, 0) == 0 else {
            return [:]
        }

        var result: [String: String] = [:]
        var offset = 0

        // The kernel returns a packed stream of rt_msghdr messages; each
        // message is followed by concatenated sockaddrs (first the IPv4
        // address, then the sockaddr_dl carrying the hardware address).
        while offset + rtMsghdrSize <= len {
            // rtm_msglen is the first field of rt_msghdr (u_short).
            let msgLen = Int(buf.load(fromByteOffset: offset, as: UInt16.self))
            guard msgLen > 0 else { break }
            // Guard against a truncated message claiming to run past the
            // end of the buffer.
            guard offset + msgLen <= len else { break }

            let sinOffset = offset + rtMsghdrSize
            guard sinOffset + MemoryLayout<sockaddr_in>.size <= offset + msgLen else {
                offset += msgLen
                continue
            }

            let sin = buf.load(fromByteOffset: sinOffset, as: sockaddr_in.self)

            var inAddr = sin.sin_addr
            var ipCStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            _ = withUnsafePointer(to: &inAddr) { ptr in
                inet_ntop(AF_INET, ptr, &ipCStr, socklen_t(INET_ADDRSTRLEN))
            }
            let ip = String(cString: ipCStr)

            // sockaddr_in lengths are variable (sin_len); round up to the
            // next 4-byte boundary to locate the following sockaddr_dl.
            let sinLen = Int(sin.sin_len)
            let alignedSinLen = (sinLen + 3) & ~3
            let sdlOffset = sinOffset + alignedSinLen

            // Bounds-check: ensure the sockaddr_dl header (8 bytes) fits
            // inside the current message.
            guard sdlOffset + 8 <= offset + msgLen else {
                offset += msgLen
                continue
            }

            // sockaddr_dl field layout:
            //   u_char  sdl_len        @ 0
            //   u_char  sdl_family     @ 1
            //   u_short sdl_index      @ 2
            //   u_char  sdl_type       @ 4
            //   u_char  sdl_nlen       @ 5   (interface name length)
            //   u_char  sdl_alen       @ 6   (link address length; 6 for Ethernet)
            //   u_char  sdl_slen       @ 7
            //   char    sdl_data[…]    @ 8   (iface name followed by link address)
            let sdlFamily = buf.load(fromByteOffset: sdlOffset + 1, as: UInt8.self)
            let sdlNlen = buf.load(fromByteOffset: sdlOffset + 5, as: UInt8.self)
            let sdlAlen = buf.load(fromByteOffset: sdlOffset + 6, as: UInt8.self)

            if sdlFamily == UInt8(AF_LINK), sdlAlen == 6 {
                let lladdrOffset = sdlOffset + 8 + Int(sdlNlen)
                if lladdrOffset + 6 <= offset + msgLen {
                    var macBytes = [UInt8](repeating: 0, count: 6)
                    for i in 0..<6 {
                        macBytes[i] = buf.load(fromByteOffset: lladdrOffset + i, as: UInt8.self)
                    }
                    // Skip all-zero MACs (unresolved ARP entries).
                    if macBytes.contains(where: { $0 != 0 }),
                       !ip.isEmpty, ip != "0.0.0.0" {
                        let mac = macBytes.map { String(format: "%02x", $0) }
                            .joined(separator: ":")
                        result[ip] = mac
                    }
                }
            }

            offset += msgLen
        }

        return result
    }

    /// Returns `true` if the MAC address is **locally administered** — i.e.,
    /// likely a privacy-randomized MAC rather than a real vendor-assigned
    /// one. iOS 14+, macOS 12+, Android 10+, and Windows 10+ all default to
    /// randomized MACs per SSID. The second-least-significant bit of the
    /// first byte is set on locally-administered MACs.
    static func isLocallyAdministered(_ mac: String) -> Bool {
        guard let firstByte = firstByteHex(mac) else { return false }
        return (firstByte & 0x02) == 0x02
    }

    /// Extracts the OUI (upper 3 bytes, 24 bits) of a MAC address as an
    /// uppercase string suitable for dictionary lookup (e.g., `"3C:22:FB"`).
    /// Returns `nil` for malformed input.
    static func oui(from mac: String) -> String? {
        let cleaned = mac
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: ":")
            .uppercased()
        let parts = cleaned.split(separator: ":")
        guard parts.count >= 3,
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 2,
              parts[0].allSatisfy(\.isHexDigit),
              parts[1].allSatisfy(\.isHexDigit),
              parts[2].allSatisfy(\.isHexDigit)
        else { return nil }
        return "\(parts[0]):\(parts[1]):\(parts[2])"
    }

    private static func firstByteHex(_ mac: String) -> UInt8? {
        let cleaned = mac
            .replacingOccurrences(of: "-", with: ":")
            .replacingOccurrences(of: ".", with: ":")
        let first = cleaned.split(separator: ":").first.map(String.init) ?? ""
        guard first.count == 2 else { return nil }
        return UInt8(first, radix: 16)
    }
}
