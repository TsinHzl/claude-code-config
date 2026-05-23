---
name: iOS Swift
description: iOS/Swift style, architecture (MVVM/Coordinator), SwiftUI vs UIKit, performance, testing rules
inclusion: auto
fileMatchPattern: "*.swift"
---

# iOS / Swift Rules

## Expertise Baseline
- 8+ years iOS — skip UIKit/SwiftUI basics
- Assume familiarity: Combine, async/await, XCTest, App Store process, provisioning/entitlements

## Swift Style
- `async/await` over completion handlers for new code
- Value types (struct/enum) > class unless identity semantics required
- `guard` early returns > nested `if` chains
- Explicit access control on all declarations
- No force unwrap (`!`) except tests or truly impossible-nil — use `guard let` / `if let`
- `Result<T, Error>` for synchronous throwing boundaries

## Architecture
- Default MVVM for new features; don't refactor working MVC unprompted
- Coordinator pattern for navigation — no navigation logic in ViewModels
- DI via initializer, not singletons (except truly global state like analytics)

## SwiftUI vs UIKit
- New UI: SwiftUI unless deployment target or feature requires UIKit
- Don't mix paradigms per screen/component
- `@StateObject` for owned models, `@ObservedObject` for injected

## Performance
- Main thread for UI only — network/disk/compute on background actors
- Instruments before optimizing
- `[weak self]` in closures that outlive their scope

## Testing
- XCTest for unit/integration; XCUITest only for critical user flows
- Mock network at URLProtocol level, not URLSession
- Snapshot tests only for complex custom UI

## Tooling
- `.xcconfig` for build settings, not Xcode GUI
- SPM > CocoaPods > Carthage for new deps
- Never commit derived data, `.DS_Store`, unencrypted `.p12`/`.mobileprovision`
- `xcodebuild` for CI
