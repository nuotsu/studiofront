import Foundation

public struct SanityConditional<Value: Sendable>: Sendable {
    public var value: Value?
    public var etag: String?
    public var notModified: Bool

    public init(value: Value?, etag: String?, notModified: Bool) {
        self.value = value
        self.etag = etag
        self.notModified = notModified
    }

    public func map<T: Sendable>(_ transform: (Value) -> T) -> SanityConditional<T> {
        SanityConditional<T>(
            value: value.map(transform),
            etag: etag,
            notModified: notModified
        )
    }
}
