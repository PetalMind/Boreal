nonisolated final class FrameRingBuffer<Element> {
    private let capacity: Int
    private var values: [Element] = []

    init(capacity: Int = 3) {
        self.capacity = max(1, capacity)
    }

    var count: Int { values.count }
    var latest: Element? { values.last }

    @discardableResult
    func append(_ value: Element) -> [Element] {
        values.append(value)
        if values.count > capacity {
            let overflowCount = values.count - capacity
            let removed = Array(values.prefix(overflowCount))
            values.removeFirst(overflowCount)
            return removed
        }
        return []
    }

    func removeFirst() -> Element? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }

    func removeAll(keepingCapacity: Bool = true) {
        values.removeAll(keepingCapacity: keepingCapacity)
    }
}
