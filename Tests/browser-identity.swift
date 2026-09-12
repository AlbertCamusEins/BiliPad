import Foundation

@main
private enum BrowserIdentityTests {
    static func main() {
        let token = BrowserIdentity.applicationNameForUserAgent(
            osVersion: OperatingSystemVersion(
                majorVersion: 18,
                minorVersion: 5,
                patchVersion: 0
            )
        )

        precondition(token == "Version/18.5 Safari/605.1.15 BiliPad/0.1")
    }
}
