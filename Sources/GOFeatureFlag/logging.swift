import Logging
import OpenFeature

/// Logger used outside of a flag evaluation, where the SDK gives us none: the data collector and
/// its hooks, which `HookContext` carries no logger for.
///
/// It is read lazily rather than captured when the provider is built, so that a logger set on the
/// SDK after `setProvider` is still picked up. When the SDK has no logger, we fall back on a default
/// one so that errors are never silently swallowed.
var providerLogger: Logger {
    return OpenFeatureAPI.shared.getLogger() ?? Logger(label: "org.gofeatureflag.provider")
}
