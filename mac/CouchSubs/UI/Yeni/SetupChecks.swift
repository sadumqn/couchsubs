// SPDX-License-Identifier: AGPL-3.0-only

import AVFoundation
import CoreWLAN
import Darwin
import Foundation
import RemotePlay

/// "PS5 Bulunamadı" ekranının kendiliğinden denetimleri (tuval 04). Okunamayan madde `unknown` kalır; tahmin yok.
struct SetupCheck: Identifiable, Equatable {
    enum State: Equatable { case passed, problem, unknown }
    enum Kind: CaseIterable { case sameNetwork, ps5Responds, remotePlay, restModeInternet, wifi5GHz, vpn }

    let kind: Kind
    let state: State
    var id: Kind { kind }

    /// Denetimleri çalıştırır. `consoles`: az önceki aramanın sonucu (aynı arama yeniden yapılmaz).
    static func run(consoles: [ConsoleInfo]) -> [SetupCheck] {
        let addresses = Interfaces.read()
        let lan = addresses.contains { $0.isPrivateIPv4 && ($0.name.hasPrefix("en") || $0.name.hasPrefix("bridge")) }
        let vpn = addresses.contains { entry in entry.isIPv4 && ["utun", "ipsec", "ppp", "tun", "tap"].contains { entry.name.hasPrefix($0) } }
        return [
            SetupCheck(kind: .sameNetwork, state: lan ? .passed : .problem),
            SetupCheck(kind: .ps5Responds, state: consoles.isEmpty ? .problem : .passed),
            // PS5'in Uzaktan Oynatma ayarı ağdan okunamaz; eşleşme denemesi söyler.
            SetupCheck(kind: .remotePlay, state: .unknown),
            // Dinlenme modundaki PS5 aramaya yalnız "İnternete Bağlı Kal" açıkken yanıt verir.
            SetupCheck(kind: .restModeInternet, state: consoles.contains { !$0.isAwake } ? .passed : .unknown),
            SetupCheck(kind: .wifi5GHz, state: wifiBand()),
            SetupCheck(kind: .vpn, state: vpn ? .problem : .passed),
        ]
    }

    /// Wi-Fi bandı (CoreWLAN); kabloyla bağlıysa ya da okunamazsa bilinmiyor.
    private static func wifiBand() -> State {
        guard let channel = CWWiFiClient.shared().interface()?.wlanChannel() else { return .unknown }
        switch channel.channelBand {
        case .band5GHz, .band6GHz: return .passed
        case .band2GHz: return .problem
        default: return .unknown
        }
    }

    private struct Interfaces {
        let name: String
        let isIPv4: Bool
        let isPrivateIPv4: Bool

        static func read() -> [Interfaces] {
            var list: [Interfaces] = []
            var head: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&head) == 0, let first = head else { return [] }
            defer { freeifaddrs(head) }
            var pointer: UnsafeMutablePointer<ifaddrs>? = first
            while let entry = pointer {
                defer { pointer = entry.pointee.ifa_next }
                guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                      (entry.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
                let name = String(cString: entry.pointee.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                let isPrivate = ip.hasPrefix("10.") || ip.hasPrefix("192.168.")
                    || (ip.hasPrefix("172.") && (16...31).contains(Int(ip.split(separator: ".").dropFirst().first ?? "") ?? 0))
                list.append(Interfaces(name: name, isIPv4: true, isPrivateIPv4: isPrivate))
            }
            return list
        }
    }
}
