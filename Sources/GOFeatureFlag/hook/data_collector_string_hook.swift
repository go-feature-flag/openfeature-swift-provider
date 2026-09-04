import Foundation
import OpenFeature
import OFREP
import Logging

class StringHook: Hook {
    typealias HookValue = String
    let dataCollectorMngr: DataCollectorManager
    let logger: Logger

    init(dataCollectorMngr: DataCollectorManager, logger: Logger) {
        self.dataCollectorMngr = dataCollectorMngr
        self.logger = logger
    }

    func before<HookValue>(ctx: HookContext<HookValue>, hints: [String: Any]) {
        return
    }

    func after<HookValue>(
        ctx: HookContext<HookValue>,
        details: FlagEvaluationDetails<HookValue>,
        hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        guard let value = details.value as? String else {
            self.logger.warning("Default value is not of type String")
            return
        }

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: details.variant ?? "SdkDefault",
            value: JSONValue.string(value),
            default: false,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func error<HookValue>(
        ctx: HookContext<HookValue>,
        error: Error,
        hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        guard let value = ctx.defaultValue as? String else {
            self.logger.warning("Default value is not of type String")
            return
        }

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: "SdkDefault",
            value: JSONValue.string(value),
            default: true,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func finally<HookValue>(
        ctx: HookContext<HookValue>, details: FlagEvaluationDetails<HookValue>, hints: [String: Any]) {
        return
    }
}
