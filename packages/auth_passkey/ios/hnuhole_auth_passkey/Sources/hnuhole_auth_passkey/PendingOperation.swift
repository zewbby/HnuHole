import Foundation

// Main-thread ownership fence, independent of the system provider callback.
final class PendingOperation<T: AnyObject> {
    private var value: T?
    func begin(_ candidate: T) -> Bool {
        guard value == nil else { return false }
        value = candidate
        return true
    }
    func take(_ candidate: T) -> T? {
        guard value === candidate else { return nil }
        value = nil
        return candidate
    }
    func cancel() -> T? {
        let previous = value
        value = nil
        return previous
    }
}
