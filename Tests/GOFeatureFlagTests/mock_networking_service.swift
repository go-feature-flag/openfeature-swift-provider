import XCTest
import Combine
import Foundation
import OpenFeature
@testable import GOFeatureFlag

class GoFeatureFlagProviderTests: XCTestCase {
    func testProviderMetadataName() async {
        let options = GoFeatureFlagProviderOptions(endpoint: "https://localhost:1031")
        let provider = GoFeatureFlagProvider(options: options)
        XCTAssertEqual(provider.metadata.name, "GO Feature Flag provider")
    }
}
