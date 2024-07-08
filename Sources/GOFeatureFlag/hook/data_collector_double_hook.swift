import Foundation
import OpenFeature
import OFREP

class DoubleHook: Hook {
    typealias HookValue = Double
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
        let value: Double = details.value as! Double

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: details.variant ?? "SdkDefault",
            value: JSONValue.double(value),
            default: false,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func error<HookValue>(ctx: HookContext<HookValue>, error: Error, hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        let value: Double = ctx.defaultValue as! Double

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: "SdkDefault",
            value: JSONValue.double(value),
            default: true,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func finallyAfter<HookValue>(ctx: HookContext<HookValue>, hints: [String: Any]) {
        return
    }
}
