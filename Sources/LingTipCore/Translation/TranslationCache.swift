import Foundation

/// Small LRU cache so repeated lookups of the same word are instant and free.
final class TranslationCache {
    private struct Key: Hashable {
        let text: String
        let pair: LanguagePair
    }

    private let capacity: Int
    private var storage: [Key: TranslationResult] = [:]
    private var order: [Key] = []

    init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    var count: Int { storage.count }

    subscript(text: String, pair: LanguagePair) -> TranslationResult? {
        get {
            let key = Key(text: text, pair: pair)
            guard let value = storage[key] else { return nil }
            touch(key)
            return value
        }
        set {
            let key = Key(text: text, pair: pair)
            guard let newValue else {
                storage.removeValue(forKey: key)
                order.removeAll { $0 == key }
                return
            }
            storage[key] = newValue
            touch(key)
            while storage.count > capacity, let oldest = order.first {
                order.removeFirst()
                storage.removeValue(forKey: oldest)
            }
        }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
