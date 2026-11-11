// SPDX-License-Identifier: AGPL-3.0-only

import Foundation

/// Uygulamanın adı ve kimlikleri tek yerde.
enum AppIdentity {
    static let name = "CouchSubs"
    static let tvAppId = "com.couchsubs.tv"
    static let samsungAppId = "CouchSubsT.CouchSubs"
    static let tvGuideURL = URL(string: "https://github.com/yorulmazsinan/couchsubs/blob/main/docs/tv-kurulum.md")!
    static let sourceURL = URL(string: "https://github.com/yorulmazsinan/couchsubs")!
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static let serverPort: UInt16 = 8787
}
