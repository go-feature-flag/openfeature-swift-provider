import OpenFeature
import OFREP

extension Value {
    public func toJSONValue() -> JSONValue {
        switch self {
        case .boolean(let bool):
            return .bool(bool)
        case .string(let string):
            return .string(string)
        case .integer(let int64):
            return .integer(int64)
        case .double(let double):
            return .double(double)
        case .date(let date):
            return .double(date.timeIntervalSinceReferenceDate)  // Represent date as a time interval
        case .list(let list):
            return .array(list.map { $0.toJSONValue() })
        case .structure(let structure):
            return .object(structure.mapValues { $0.toJSONValue() })
        case .null:
            return .null
        }
    }
}
