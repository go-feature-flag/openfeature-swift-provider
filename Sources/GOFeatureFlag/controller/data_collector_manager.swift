import Foundation
import OpenFeature
import Combine

class DataCollectorManager {
    var events: [FeatureEvent] = []
    var hooks: [any Hook] = []
    let queue = DispatchQueue(label: "org.gofeatureflag.feature.events", attributes: .concurrent)
    let goffAPI: GoFeatureFlagAPI
    let options: GoFeatureFlagProviderOptions
    private var timer: DispatchSourceTimer?

    init(goffAPI: GoFeatureFlagAPI, options: GoFeatureFlagProviderOptions) {
        self.goffAPI = goffAPI
        self.options = options
    }

    func start() {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer?.schedule(deadline: .now(), repeating: self.options.dataCollectorInterval, leeway: .milliseconds(100))
        timer?.setEventHandler { [weak self] in
            guard let weakSelf = self else { return }
            Task {
                await weakSelf.pushEvents()
            }
        }
        timer?.resume()
    }

    func appendFeatureEvent(event: FeatureEvent) {
        self.queue.async(flags:.barrier) {
            self.events.append(event)
        }
    }

    func pushEvents() async {
        // Drain the buffer atomically before posting. Previously the barrier
        // block spawned a detached Task and returned immediately, so the read
        // of `events` and the `events = []` after the network call were not
        // synchronised with appendFeatureEvent: any event recorded while a
        // post was in flight was silently discarded.
        let pending: [FeatureEvent] = self.queue.sync(flags: .barrier) {
            let current = self.events
            self.events = []
            return current
        }
        guard !pending.isEmpty else { return }
        do {
            (_, _) = try await self.goffAPI.postDataCollector(events: pending)
        } catch {
            providerLogger.error("data collector error: \(error)")
        }
    }

    func getHooks() -> [any Hook] {
        return self.hooks
    }

    func stop() async {
        await self.pushEvents()
    }
}
