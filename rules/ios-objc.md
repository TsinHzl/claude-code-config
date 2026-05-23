---
name: iOS Objective-C
description: Objective-C style, memory management, patterns, Swift interop, error handling rules
inclusion: auto
fileMatchPattern: ["*.m", "*.h", "*.mm"]
---

# iOS / Objective-C Rules

## Expertise Baseline
- Legacy/enterprise ObjC codebase — assume familiarity with runtime, KVO, delegation, categories
- Mixed ObjC+Swift projects are common; bridging header rules apply

## ObjC Style
- Nullability annotations on all public headers: `NS_ASSUME_NONNULL_BEGIN/END`, explicit `nullable` where needed
- `NS_ENUM` / `NS_OPTIONS` over raw `typedef enum`
- Dot syntax for properties only, bracket syntax for methods
- No `@synthesize` unless overriding both getter and setter
- `instancetype` over `id` for init/factory methods
- Prefix all classes/categories/constants with project 2-3 letter prefix to avoid symbol collisions

## Memory Management
- ARC only — no manual `retain`/`release` in new code
- `__weak` for delegates and callback blocks to avoid retain cycles
- `__strong` capture in blocks when you need to extend lifetime, paired with `__weak` pre-capture
- `@autoreleasepool` in tight loops processing large data

## Patterns
- Delegate pattern for 1:1 callbacks; `NSNotification` only for truly broadcast events
- Category for extending existing classes; avoid swizzling unless absolutely necessary
- `dispatch_once` for singletons
- `NSOperation`/`NSOperationQueue` for complex async dependency graphs; GCD for simple background work

## Interop with Swift
- Expose ObjC APIs to Swift via `NS_SWIFT_NAME` for clean Swift call sites
- Mark ObjC-only APIs with `NS_UNAVAILABLE` in Swift where bridging is unsafe
- Avoid `id` in headers that bridge to Swift — use typed pointers or generics (`NSArray<NSString *>`)

## Error Handling
- `NSError **` out-param pattern for recoverable errors; exceptions only for programmer errors
- Always check return value before dereferencing `NSError`
- Define error domains as `extern NSString * const` in headers

## Testing
- XCTest for unit tests; OCMock for mocking ObjC objects
- Test categories/extensions in separate `*+Testing` files, not production headers

## Tooling
- `clang-format` with project `.clang-format` for consistent formatting
- Static analyzer (`Product > Analyze`) must pass clean before PR
- Never commit `.orig` merge artifacts or auto-generated `*-Swift.h` bridging headers
