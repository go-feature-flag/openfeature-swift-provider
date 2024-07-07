import XCTest
import Combine
import Foundation
import OpenFeature
@testable import GOFeatureFlag

class GoFeatureFlagProviderTests: XCTestCase {
    var defaultEvaluationContext: MutableContext!
    var cancellables: Set<AnyCancellable> = []
    func testShouldBeInFATALStatusIf401ErrorDuringInitialise() async {
        print("toto")
    }
}
