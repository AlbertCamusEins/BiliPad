import Foundation

@main
private enum NavigationErrorPolicyTests {
    static func main() {
        let cancellation = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cancelled.rawValue
        )
        let timeout = NSError(
            domain: NSURLErrorDomain,
            code: URLError.timedOut.rawValue
        )

        precondition(!NavigationErrorPolicy.shouldReport(cancellation))
        precondition(NavigationErrorPolicy.shouldReport(timeout))
    }
}
