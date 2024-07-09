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
        self.queue.async(flags:.barrier) {
            Task {
                do {
                    if !self.events.isEmpty {
                        (_,_) = try await self.goffAPI.postDataCollector(events: self.events)
                        self.events = []
                    }
                } catch {
                    NSLog("data collector error: \(error)")
                }
            }
        }
    }

    func getHooks() -> [any Hook] {
        return self.hooks
    }

    func stop() async {
        await self.pushEvents()
    }
}
