import Foundation
import OpenFeature
import OFREP

class IntegerHook: Hook {
    typealias HookValue = Int64
    let dataCollectorMngr: DataCollectorManager

    init(dataCollectorMngr: DataCollectorManager) {
        self.dataCollectorMngr = dataCollectorMngr
    }

    func before<HookValue>(ctx: HookContext<HookValue>, hints: [String: Any]) {
        return
    }

    func after<HookValue>(ctx: HookContext<HookValue>, details: FlagEvaluationDetails<HookValue>, hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        let value: Int64 = details.value as! Int64

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: details.variant ?? "SdkDefault",
            value: JSONValue.integer(value),
            default: false,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func error<HookValue>(ctx: HookContext<HookValue>, error: Error, hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        let value: Int64 = ctx.defaultValue as! Int64

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: "SdkDefault",
            value: JSONValue.integer(value),
            default: true,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func finallyAfter<HookValue>(ctx: HookContext<HookValue>, hints: [String: Any]) {
        return
    }
}
