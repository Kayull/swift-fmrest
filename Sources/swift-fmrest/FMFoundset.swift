import Foundation

public struct FMFoundset: RandomAccessCollection, Equatable, Sendable {
    public typealias Element = FMRecord
    public typealias Index = Int

    public var records: [FMRecord]
    public var info: [String: FMValue]

    public init(records: [FMRecord], info: [String: FMValue] = [:]) {
        self.records = records
        self.info = info
    }

    public var startIndex: Int { records.startIndex }
    public var endIndex: Int { records.endIndex }

    public subscript(position: Int) -> FMRecord {
        records[position]
    }
}

