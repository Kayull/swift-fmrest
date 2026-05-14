import Foundation

public enum FMValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: FMValue])
    case array([FMValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([FMValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: FMValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String? {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            String(value)
        case let .double(value):
            String(value)
        case let .bool(value):
            value ? "true" : "false"
        case .object, .array, .null:
            nil
        }
    }

    public var intValue: Int? {
        switch self {
        case let .int(value):
            value
        case let .string(value):
            Int(value)
        case let .double(value):
            Int(value)
        case .bool, .object, .array, .null:
            nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case let .double(value):
            value
        case let .int(value):
            Double(value)
        case let .string(value):
            Double(value)
        case .bool, .object, .array, .null:
            nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case let .bool(value):
            value
        case let .string(value):
            Bool(value)
        case .int, .double, .object, .array, .null:
            nil
        }
    }

    public var objectValue: [String: FMValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [FMValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

extension FMValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension FMValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension FMValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension FMValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension FMValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: FMValue...) {
        self = .array(elements)
    }
}

extension FMValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, FMValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

extension FMValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension FMValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            String(value)
        case let .double(value):
            String(value)
        case let .bool(value):
            String(value)
        case let .object(value):
            String(describing: value)
        case let .array(value):
            String(describing: value)
        case .null:
            "null"
        }
    }
}
