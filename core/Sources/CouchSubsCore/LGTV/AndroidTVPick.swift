// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Ağda hata ayıklaması açık bulunan Android TV'ler arasından kurulumun gideceği TV (Windows: AndroidTvPick).
/// Eskiden ilk bulunan seçiliyordu; aynı evde iki Android TV varken izin sorusu başka odadaki TV'de çıkıyor, kurulum
/// "onaylanmadı" diye bitiyordu (GitHub #425).
public enum AndroidTVPick: Equatable, Sendable {
    /// Hata ayıklaması açık TV yok.
    case none
    case host(String)
    /// Birden çok TV var ve hangisi olduğu bilinmiyor: kullanıcıya sorulur.
    case ask([String])

    /// `preferred`: kullanıcının seçtiği ya da kayıtlı TV adresi (önce gelen önce). Bulunanlar arasındaysa o seçilir;
    /// tek TV bulunduysa odur; birden çoksa sorulur.
    public static func pick(found: [String], preferred: [String]) -> AndroidTVPick {
        var hosts: [String] = []
        for host in found where !host.isEmpty && !hosts.contains(host) { hosts.append(host) }
        if let known = preferred.first(where: { !$0.isEmpty && hosts.contains($0) }) { return .host(known) }
        switch hosts.count {
        case 0: return .none
        case 1: return .host(hosts[0])
        default: return .ask(hosts)
        }
    }
}
