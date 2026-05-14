import Foundation

public struct FMScriptCall: Equatable, Sendable {
    public var name: String
    public var parameter: String?

    public init(_ name: String, parameter: String? = nil) {
        self.name = name
        self.parameter = parameter
    }
}

public struct FMScripts: Equatable, Sendable {
    public var prerequest: FMScriptCall?
    public var presort: FMScriptCall?
    public var after: FMScriptCall?

    public init(
        prerequest: FMScriptCall? = nil,
        presort: FMScriptCall? = nil,
        after: FMScriptCall? = nil
    ) {
        self.prerequest = prerequest
        self.presort = presort
        self.after = after
    }

    internal var valueParameters: [String: FMValue] {
        var output: [String: FMValue] = [:]
        if let prerequest {
            output["script.prerequest"] = .string(prerequest.name)
            if let parameter = prerequest.parameter {
                output["script.prerequest.param"] = .string(parameter)
            }
        }
        if let presort {
            output["script.presort"] = .string(presort.name)
            if let parameter = presort.parameter {
                output["script.presort.param"] = .string(parameter)
            }
        }
        if let after {
            output["script"] = .string(after.name)
            if let parameter = after.parameter {
                output["script.param"] = .string(parameter)
            }
        }
        return output
    }

    internal var queryParameters: [String: String] {
        valueParameters.compactMapValues(\.stringValue)
    }
}

public enum FMSortOrder: String, Codable, Sendable {
    case ascend
    case descend
}

public struct FMSort: Codable, Equatable, Sendable {
    public var fieldName: String
    public var sortOrder: FMSortOrder

    public init(fieldName: String, sortOrder: FMSortOrder) {
        self.fieldName = fieldName
        self.sortOrder = sortOrder
    }

    internal var value: FMValue {
        .object([
            "fieldName": .string(fieldName),
            "sortOrder": .string(sortOrder.rawValue),
        ])
    }
}

public struct FMPortalRequest: Equatable, Sendable {
    public var name: String
    public var offset: Int
    public var limit: Int

    public init(name: String, offset: Int = 1, limit: Int = 50) {
        self.name = name
        self.offset = offset
        self.limit = limit
    }
}

public struct FMScriptResult: Equatable, Sendable {
    public var error: Int?
    public var result: String?

    public init(error: Int?, result: String?) {
        self.error = error
        self.result = result
    }
}

public struct FMFetchedFile: Equatable, Sendable {
    public var filename: String
    public var contentType: String?
    public var contentLength: Int?
    public var data: Data

    public init(filename: String, contentType: String?, contentLength: Int?, data: Data) {
        self.filename = filename
        self.contentType = contentType
        self.contentLength = contentLength
        self.data = data
    }
}

