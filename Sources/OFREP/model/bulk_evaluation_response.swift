import OpenFeature

struct EvaluationResponseDTO: Codable {
    var flags: [EvaluationResponseFlagDTO]?
    let errorCode: String?
    let errorDetails: String?
}

struct EvaluationResponseFlagDTO: Codable {
    let value: JSONValue?
    let key: String?
    let reason: String?
    let variant: String?
    let errorCode: String?
    let errorDetails: String?
    let metadata: [String:FlagMetadataValueDto]?
}

enum FlagMetadataValueDto: Codable {
    case boolean(Bool)
    case string(String)
    case integer(Int64)
    case double(Double)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let boolValue = try? container.decode(Bool.self) {
            self = .boolean(boolValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else if let intValue = try? container.decode(Int64.self) {
            self = .integer(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else {
            throw DecodingError.typeMismatch(
                FlagMetadataValueDto.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unexpected value found for IntermediateFlagMetadataValue")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .boolean(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        }
    }

    func toFlagMetadataValue() -> FlagMetadataValue? {
        switch self {
        case .boolean(let value): return .boolean(value)
        case .string(let value): return .string(value)
        case .integer(let value): return .integer(value)
        case .double(let value): return .double(value)
        }
    }
}

struct OfrepEvaluationResponse {
    let flags: [OfrepEvaluationResponseFlag]
    let errorCode: ErrorCode?
    let errorDetails: String?

    func isError() -> Bool {
        return errorCode != nil
    }

    static func fromEvaluationResponseDTO(dto: EvaluationResponseDTO) -> OfrepEvaluationResponse {
        var flagsConverted: [OfrepEvaluationResponseFlag] = []
        var errCode: ErrorCode?
        let errDetails = dto.errorDetails

        if let flagsDTO = dto.flags {
            for flag in flagsDTO {
                var errorCode: ErrorCode?
                if let erroCodeValue = flag.errorCode {
                    errorCode = convertErrorCode(code: erroCodeValue)
                }

                var convertedMetadata: [String: FlagMetadataValue]?
                if let metadata = flag.metadata {
                    convertedMetadata = Dictionary(uniqueKeysWithValues: metadata.map { key, value in
                        (key, value.toFlagMetadataValue())
                    }.compactMap { (key, value) -> (String, FlagMetadataValue)? in
                        guard let value = value else { return nil }
                        return (key, value)
                    })
                }

                flagsConverted.append(OfrepEvaluationResponseFlag(
                    value: flag.value,
                    key: flag.key,
                    reason: flag.reason,
                    variant: flag.variant,
                    errorCode: errorCode,
                    errorDetails: flag.errorDetails,
                    flagMetadata: convertedMetadata
                ))
            }
        }

        if let errorCode = dto.errorCode {
            errCode = convertErrorCode(code: errorCode)
        }

        return OfrepEvaluationResponse(flags: flagsConverted, errorCode: errCode, errorDetails: errDetails)
    }

    static func convertErrorCode(code: String) -> ErrorCode {
        switch code {
        case "PROVIDER_NOT_READY":
            return ErrorCode.providerNotReady
        case "FLAG_NOT_FOUND":
            return ErrorCode.flagNotFound
        case "PARSE_ERROR":
            return ErrorCode.parseError
        case "TYPE_MISMATCH":
            return ErrorCode.typeMismatch
        case "TARGETING_KEY_MISSING":
            return ErrorCode.targetingKeyMissing
        case "INVALID_CONTEXT":
            return ErrorCode.invalidContext
        default:
            return ErrorCode.general
        }
    }
}

struct OfrepEvaluationResponseFlag {
    let value: JSONValue?
    let key: String?
    let reason: String?
    let variant: String?
    let errorCode: ErrorCode?
    let errorDetails: String?
    let flagMetadata: [String:FlagMetadataValue]?

    func isError() -> Bool {
        return errorCode != nil
    }
}
