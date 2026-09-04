import Foundation
import OpenFeature
import OFREP
import Logging

class ObjectHook: Hook {
    typealias HookValue = Value
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
        guard let valueRaw = details.value as? Value else {
            self.logger.warning("Default value is not of type Object")
            return
        }
        let value: JSONValue = valueRaw.toJSONValue()

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: details.variant ?? "SdkDefault",
            value: value,
            default: false,
            source: "PROVIDER_CACHE"
        )
        self.dataCollectorMngr.appendFeatureEvent(event: event)
    }

    func error<HookValue>(ctx: HookContext<HookValue>, error: Error, hints: [String: Any]) {
        let contextKind = "user"
        let userKey = ctx.ctx?.getTargetingKey() ?? ""
        let key = ctx.flagKey
        guard let valueRaw = ctx.defaultValue as? Value else {
            self.logger.warning("Default value is not of type Object")
            return
        }
        let value: JSONValue = valueRaw.toJSONValue()

        let event = FeatureEvent(
            kind: "feature",
            contextKind: contextKind,
            userKey: userKey,
            creationDate: Int64(Date().timeIntervalSince1970),
            key: key,
            variation: "SdkDefault",
            value: value,
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
