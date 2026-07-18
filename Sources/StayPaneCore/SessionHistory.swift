import Foundation

public enum SessionResult: String, Codable, Equatable, Sendable {
    case completed
    case endedEarly
    case interrupted
}

public struct SessionHistoryRecord: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let plannedDuration: SessionDuration
    public let actualFocusTime: TimeInterval
    public let result: SessionResult

    public init(
        startedAt: Date,
        plannedDuration: SessionDuration,
        actualFocusTime: TimeInterval,
        result: SessionResult
    ) {
        self.startedAt = startedAt
        self.plannedDuration = plannedDuration
        self.actualFocusTime = min(
            plannedDuration.timeInterval,
            max(0, actualFocusTime)
        )
        self.result = result
    }
}

@MainActor
public protocol SessionHistoryStoring: AnyObject {
    func load() throws -> [SessionHistoryRecord]
    func record(_ record: SessionHistoryRecord) throws
    func clear() throws
}

@MainActor
public final class NoSessionHistoryStore: SessionHistoryStoring {
    public init() {}

    public func load() throws -> [SessionHistoryRecord] {
        []
    }

    public func record(_ record: SessionHistoryRecord) throws {}

    public func clear() throws {}
}

@MainActor
public final class SessionHistoryController {
    public private(set) var records: [SessionHistoryRecord] = []
    public private(set) var isClearConfirmationPresented = false

    private let store: any SessionHistoryStoring

    public init(store: any SessionHistoryStoring) {
        self.store = store
    }

    public func reload() throws {
        records = try store.load()
    }

    public func requestClear() {
        isClearConfirmationPresented = true
    }

    public func cancelClear() {
        isClearConfirmationPresented = false
    }

    @discardableResult
    public func confirmClear() throws -> Bool {
        guard isClearConfirmationPresented else {
            return false
        }
        try store.clear()
        records = []
        isClearConfirmationPresented = false
        return true
    }
}
