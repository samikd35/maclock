import Foundation

struct TargetReusePartition<ID: Hashable & Sendable>: Equatable, Sendable {
    let retained: [ID]
    let dropped: [ID]
}

enum TargetReusePolicy {
    static func partition<ID: Hashable & Sendable>(
        previousIDs: [ID],
        availableIDs: [ID]
    ) -> TargetReusePartition<ID> {
        let availableIDSet = Set(availableIDs)
        var retained: [ID] = []
        var dropped: [ID] = []
        for identifier in previousIDs {
            if availableIDSet.contains(identifier) {
                retained.append(identifier)
            } else {
                dropped.append(identifier)
            }
        }
        return TargetReusePartition(
            retained: retained,
            dropped: dropped
        )
    }
}
