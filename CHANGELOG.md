# Changelog

## [1.0.0](https://github.com/go-feature-flag/openfeature-swift-provider/compare/openfeature-swift-provider-v0.6.0...openfeature-swift-provider-v1.0.0) (2026-10-08)


### ⚠ BREAKING CHANGES

* the provider no longer depends on swift-log. Pass an `OpenFeatureLogger` to `OpenFeatureAPI.shared.setLogger`, or wrap a swift-log `Logger` with `SwiftLogLogger` from the SDK's `OpenFeatureSwiftLog` product. Without a logger the provider is silent.

### Features

* upgrade OpenFeature Swift SDK to 0.7.0 ([#34](https://github.com/go-feature-flag/openfeature-swift-provider/issues/34)) ([0ecb1fe](https://github.com/go-feature-flag/openfeature-swift-provider/commit/0ecb1fe498205f210029fd20b1db567dec451d22))

## [0.6.0](https://github.com/go-feature-flag/openfeature-swift-provider/compare/openfeature-swift-provider-v0.5.0...openfeature-swift-provider-v0.6.0) (2026-09-16)


### Features

* support the OpenFeature tracking API ([#30](https://github.com/go-feature-flag/openfeature-swift-provider/issues/30)) ([c95db41](https://github.com/go-feature-flag/openfeature-swift-provider/commit/c95db4183e67bef8f483f93624d5d983cd11fc00))


### Dependencies & Maintenance

* Bump github.com/apple/swift-log from 1.6.3 to 1.15.1 ([#29](https://github.com/go-feature-flag/openfeature-swift-provider/issues/29)) ([4147329](https://github.com/go-feature-flag/openfeature-swift-provider/commit/41473294f4eb58c768f80d871e2f71a133739a72))
