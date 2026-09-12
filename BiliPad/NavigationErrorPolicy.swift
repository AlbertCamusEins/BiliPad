import Foundation

enum NavigationErrorPolicy {
    static func shouldReport(_ error: Error) -> Bool {
        let cocoaError = error as NSError
        return !(
            cocoaError.domain == NSURLErrorDomain
                && cocoaError.code == URLError.cancelled.rawValue
        )
    }
}
