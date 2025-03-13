# GO Feature Flag - OpenFeature Swift provider
<p align="center">
   <a href="https://github.com/go-feature-flag/openfeature-swift-provider/actions/workflows/swift.yaml"><img src="https://github.com/go-feature-flag/openfeature-swift-provider/actions/workflows/swift.yaml/badge.svg" alt="CI"></a>
   <a href="https://codecov.io/gh/go-feature-flag/openfeature-swift-provider"><img src="https://codecov.io/gh/go-feature-flag/openfeature-swift-provider/graph/badge.svg?token=G6BAIREGQN" alt="codecov"></a>
   <a href="https://github.com/go-feature-flag/openfeature-swift-provider/releases"><img src="https://img.shields.io/github/v/release/go-feature-flag/openfeature-swift-provider?label=Package%20version&amp;display_name=tag&amp;logo=Swift" alt="GitHub Release"></a>
   <a href="https://gofeatureflag.org/slack"><img src="https://img.shields.io/badge/join-us%20on%20slack-gray.svg?longCache=true&logo=slack&colorB=green" alt="Join us on slack"></a>
</p>

This repository contains the official Swift OpenFeature provider for accessing your feature flags with [GO Feature Flag](https://gofeatureflag.org).

In conjuction with the [OpenFeature SDK](https://openfeature.dev/docs/reference/concepts/provider) you will be able to evaluate your feature flags in your **iOS**/**tvOS**/**macOS** applications.

For documentation related to flags management in GO Feature Flag, refer to the [GO Feature Flag documentation website](https://gofeatureflag.org/docs).

### Functionalities:
- Manage the integration of the OpenFeature Swift SDK and GO Feature Flag relay-proxy.
- Prefetch and cache flag evaluations in order to give the flag value in a efficient way.
- Automatic configuration changes polling, to be informed as soon as a flag configuration has changed.
- Automatic data collection about which flags have been accessed by the application


## Dependency Setup

### Swift Package Manager

In the dependencies section of `Package.swift` add:
```swift
.package(url: "https://github.com/go-feature-flag/openfeature-swift-provider.git", from: "0.3.0")
```

and in the target dependencies section add:
```swift
.product(name: "GOFeatureFlag", package: "openfeature-swift-provider"),  
```

### Xcode Dependencies

You have two options, both start from File > Add Packages... in the code menu.

First, ensure you have your GitHub account added as an option (+ > Add Source Control Account...). You will need to create a [Personal Access Token](https://github.com/settings/tokens) with the permissions defined in the Xcode interface.

1. Add as a remote repository
    * Search for `git@github.com:go-feature-flag/openfeature-swift-provider.git` and click "Add Package"
2. Clone the repository locally
    * Clone locally using your preferred method
    * Use the "Add Local..." button to select the local folder

**Note:** Option 2 is only recommended if you are making changes to the SDK. You will also need to add the relevant OpenFeature SDK dependency manually.

## Getting started

### Initialize the provider

GO Feature Flag provider needs to be created and then set in the global OpenFeatureAPI. 

The only required option to create a `GoFeatureFlagProvider` is the URL to your GO Feature Flag relay-proxy instance.

```swift
import GOFeatureFlag
import OpenFeature


let options = GoFeatureFlagProviderOptions(endpoint: "https://your_domain.io")
let provider = GoFeatureFlagProvider(options: options)

let evaluationContext = MutableContext(targetingKey: "myTargetingKey", structure: MutableStructure())
OpenFeatureAPI.shared.setProvider(provider: provider, initialContext: evaluationContext)
```

The evaluation context is the way for the client to specify contextual data that GO Feature Flag uses to evaluate the feature flags, it allows to define rules on the flag.

The `targetingKey` is mandatory for GO Feature Flag in order to evaluate the feature flag, it could be the id of a user, a session ID or anything you find relevent to use as identifier during the evaluation.

The `setProvider()` function is synchronous and returns immediately, however this does not mean that the provider is ready to be used. An asynchronous network request to the GO Feature Flag backend to fetch all the flags configured for your application must be completed by the provider first. The provider will then emit a `READY` event indicating you can start resolving flags.

If you prefer to wait until the fetch is done you can use the `async/await` compatible API available for waiting the Provider to become ready:

```swift
await OpenFeatureAPI.shared.setProviderAndWait(provider: provider)
```

### Update the Evaluation Context

During the usage of your application it may appears that the `EvaluationContext` should be updated. For example if a not logged in user, authentify himself you will probably have to update the evaluation context.

```swift
let ctx = MutableContext(targetingKey: "myNewTargetingKey", structure: MutableStructure())
OpenFeatureAPI.shared.setEvaluationContext(evaluationContext: ctx)
```

`setEvaluationContext()` is a synchronous function similar to `setProvider()` and will fetch the new version of the feature flags based on this new `EvaluationContext`.

### Evaluate a feature flag
The client is used to retrieve values for the current `EvaluationContext`. For example, retrieving a boolean value for the flag **"my-flag"**:

```swift
let client = OpenFeatureAPI.shared.getClient()
let result = client.getBooleanValue(key: "my-flag", defaultValue: false)
```

GO Feature Flag supports different all OpenFeature supported types of feature flags, it means that you can use all the accessor directly
```swift
// Bool
client.getBooleanValue(key: "my-flag", defaultValue: false)

// String
client.getStringValue(key: "my-flag", defaultValue: "default")

// Integer
client.getIntegerValue(key: "my-flag", defaultValue: 1)

// Double
client.getDoubleValue(key: "my-flag", defaultValue: 1.1)

// Object
client.getObjectValue(key: "my-flag", defaultValue: Value.structure(["key":Value.integer("1234")])
```

> [!NOTE]  
> If you add a new flag in GO Feature Flag, expect some delay before having it available for the provider.
> Refreshing the cache from remote happens when setting a new provider and/or evaluation context in the global OpenFeatureAPI, but also when a configuration change is detected during the polling.

### Handling Provider Events

When setting the provider or the context *(via `setEvaluationContext()` or `setProvider()`)* some events can be triggered to know the state of the provider.

To listen to them you can add an event handler via the `OpenFeatureAPI` shared instance:

```swift
OpenFeatureAPI.shared.observe().sink { event in
    if event == .error {
        // An error has been emitted
    }
}
```

#### Existing type of events are:
- `.ready`: Provider is ready.
- `.error`: Provider in error.
- `.configurationChanged`: Configuration has changed in GO Feature Flag.
- `.PROVIDER_STALE`: Provider has not the latest version of the feature flags.
- `.notReady`: Provider is not ready to evaluate the feature flags.

