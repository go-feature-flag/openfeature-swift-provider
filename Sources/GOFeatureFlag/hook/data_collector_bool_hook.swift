import Foundation
import OpenFeature
import OFREP

class BooleanHook: Hook {
    typealias HookValue = Bool
    let dataCollectorMngr: DataCollectorManager

    init(dataCollectorMngr: DataCollectorManager) {
        self.dataCollectorMngr = dataCollectorMngr
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
        guard let value = details.value as? Bool else {
            NSLog("Default value is not of type Bool")
            return
        }

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: details.variant ?? "SdkDefault",
            value: JSONValue.bool(value),
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
        guard let value = ctx.defaultValue as? Bool else {
            NSLog("Default value is not of type Bool")
            return
        }

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: "SdkDefault",
            value: JSONValue.bool(value),
            default: true,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func finallyAfter<HookValue>(ctx: HookContext<HookValue>, hints: [String: Any]) {
        return
    }
}
