import Foundation

enum BrowserIdentity {
    static func applicationNameForUserAgent(
        osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) -> String {
        let safariVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion)"
        return "Version/\(safariVersion) Safari/605.1.15 BiliPad/0.1"
    }
}
