---
name: Mobile Development General
description: Cross-platform mobile rules for battery, network, storage, UI, security, and release
inclusion: auto
---

# Mobile Development — General Rules

## Mindset
- Mobile-first: battery, memory, network are constrained — always consider cost of operations
- Offline-first where feasible: assume network is unreliable, cache aggressively
- User perception > actual performance: 60fps UI matters more than backend latency

## Networking
- All network calls async, never block main thread
- Exponential backoff + jitter for retries; max 3 retries for transient errors
- Timeout every request — no indefinite waits
- Certificate pinning for sensitive endpoints
- Never log full request/response bodies in production builds

## Data & Storage
- Sensitive data (tokens, PII) in Keychain/Keystore only — never `UserDefaults`/`SharedPreferences`
- Encrypt local DB if it contains user data
- Paginate any list that could exceed 50 items — never load unbounded datasets
- Clear cached data on logout

## UI / UX
- Support Dynamic Type / font scaling — no hardcoded font sizes in production UI
- Dark mode support unless explicitly out of scope
- Minimum tap target: 44×44pt (iOS) / 48×48dp (Android/Flutter)
- Loading states, empty states, and error states are required — not optional
- Keyboard avoidance: inputs must remain visible when keyboard appears

## App Lifecycle
- Save state on background transition; restore on foreground
- Handle memory warnings — release non-critical caches
- Deep links and push notification payloads must be validated before use

## Security
- No secrets in source code or `Info.plist`/`AndroidManifest.xml`
- Obfuscate release builds
- Disable logging in release builds (`DEBUG` flag guard)
- Screenshot prevention on sensitive screens (payment, auth)

## Release
- Semantic versioning: `MAJOR.MINOR.PATCH` + build number
- Separate bundle IDs for dev/staging/prod
- Never ship with debug flags, test accounts, or hardcoded staging URLs
