import OpenFeature

/// Evaluates, through `client`, one flag of the wrong type for each of the 5 flag types, so that every
/// typed evaluation method of the provider logs its type mismatch.
///
/// Going through the client (and not calling the provider directly) is what makes this useful: the
/// SDK only hands its logger to a provider method that matches the `FeatureProvider` requirement, a
/// method with another `logger:` type would be skipped and the provider would silently not log.
///
/// - Returns: the message each evaluation is expected to log.
public func evaluateEveryTypeWithTheWrongType(
    client: Client, options: FlagEvaluationOptions = FlagEvaluationOptions()
) -> [String] {
    _ = client.getBooleanDetails(key: "string-flag", defaultValue: false, options: options)
    _ = client.getStringDetails(key: "bool-flag", defaultValue: "default", options: options)
    _ = client.getIntegerDetails(key: "string-flag", defaultValue: 1, options: options)
    _ = client.getDoubleDetails(key: "string-flag", defaultValue: 1.0, options: options)
    _ = client.getObjectDetails(key: "bool-flag", defaultValue: Value.null, options: options)
    return [
        "flag string-flag is not a boolean",
        "flag bool-flag is not a string",
        "flag string-flag is not an integer",
        "flag string-flag is not a double",
        "flag bool-flag is neither an object nor a list"
    ]
}
