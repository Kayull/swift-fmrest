import Foundation

@dynamicMemberLookup
public struct FMRecord: Equatable, Sendable {
    public private(set) var fields: [String: FMValue]
    public private(set) var portals: [String: FMFoundset]
    public let isPortalRecord: Bool
    private var modifiedFields: [String: FMValue]

    public init(
        fields: [String: FMValue],
        portals: [String: FMFoundset] = [:],
        isPortalRecord: Bool = false
    ) {
        self.fields = fields
        self.portals = portals
        self.isPortalRecord = isPortalRecord
        self.modifiedFields = [:]
    }

    public subscript(_ field: String) -> FMValue? {
        fields[field]
    }

    public subscript(dynamicMember field: String) -> FMValue? {
        fields[field]
    }

    public var recordID: Int? {
        fields["recordId"]?.intValue
    }

    public var modificationID: Int? {
        guard !isPortalRecord else { return nil }
        return fields["modId"]?.intValue
    }

    public var isDirty: Bool {
        !modifiedFields.isEmpty
    }

    public var modifications: [String: FMValue] {
        modifiedFields
    }

    public mutating func setValue(_ value: FMValue, forField field: String) throws {
        guard fields.keys.contains(field) else {
            throw FMError.recordError("No field named \(field). The Data API only returns fields placed on the FileMaker layout.")
        }

        guard !field.hasPrefix("portal_") else {
            throw FMError.recordError("Portal data cannot be set through FMRecord. Pass portal data to editRecord instead.")
        }

        guard fields[field] != value else { return }
        fields[field] = value
        modifiedFields[field] = value
    }

    public func portal(named name: String) -> FMFoundset? {
        portals[name]
    }

    public func toDictionary(
        ignorePortals: Bool = false,
        ignoreInternalIDs: Bool = false
    ) -> [String: FMValue] {
        var output = fields

        if !ignorePortals {
            for (name, foundset) in portals {
                output["portal_\(name)"] = .array(foundset.records.map { .object($0.toDictionary(ignorePortals: true)) })
            }
        }

        if ignoreInternalIDs {
            output.removeValue(forKey: "recordId")
            output.removeValue(forKey: "modId")
        }

        return output
    }

    public func decoded<T: Decodable>(
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder(),
        ignoreInternalIDs: Bool = true
    ) throws -> T {
        let data = try JSONEncoder().encode(
            FMValue.object(toDictionary(ignorePortals: true, ignoreInternalIDs: ignoreInternalIDs))
        )
        return try decoder.decode(type, from: data)
    }
}

