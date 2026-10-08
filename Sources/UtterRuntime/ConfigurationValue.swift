import Foundation

package enum ConfigurationValue: Codable, Equatable {
    case string(String)
    case bool(Bool)
    case number(Double)
    case array([ConfigurationValue])
    case object([String: ConfigurationValue])
    case null

    package init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([ConfigurationValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: ConfigurationValue].self)) }
    }

    package func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .bool(let bool): try value.encode(bool)
        case .number(let number): try value.encode(number)
        case .array(let array): try value.encode(array)
        case .object(let object): try value.encode(object)
        case .null: try value.encodeNil()
        }
    }
}
