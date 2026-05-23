---
name: Flutter Dart
description: Flutter/Dart style, architecture (BLoC/Riverpod), performance, testing, tooling rules
inclusion: auto
fileMatchPattern: "*.dart"
---

# Flutter / Dart Rules

## Expertise Baseline
- Senior Flutter architect — skip widget basics, assume deep familiarity with state management, platform channels, pub ecosystem, and large-scale app architecture

## Dart Style
- Strong typing everywhere — no `dynamic` unless interop forces it
- `const` constructors wherever possible
- Named parameters for 2+ args; required named params over positional
- Prefer `sealed class` / pattern matching (Dart 3+) over enum + switch hacks
- No `late` unless truly deferred init — prefer nullable + null-check

## Architecture
- Default to feature-first folder structure, not layer-first
- BLoC for complex state; Riverpod for simpler/mid-complexity; avoid Provider in new code
- Repository pattern for data layer — widgets never call APIs directly
- Use `freezed` for data models and union types

## Flutter Specifics
- `const` widgets aggressively to minimize rebuilds
- `StatelessWidget` > `StatefulWidget` — lift state up or use state management
- `ListView.builder` / `SliverList` for any list that could exceed ~20 items
- Platform-specific code via method channels or `dart:io` Platform checks, not `kIsWeb` hacks
- `go_router` for navigation in new projects

## Performance
- Profile on real device, not simulator
- Avoid `setState` in large widget trees — scope rebuilds
- `RepaintBoundary` for expensive custom painters
- Image caching: `cached_network_image`, not raw `Image.network`

## Testing
- `flutter_test` for unit + widget tests
- `integration_test` only for critical flows
- Mock dependencies with `mocktail`, not `mockito`
- Golden tests only for design-system-level components

## Tooling
- `flutter analyze` + `dart fix` before committing
- `flutter_lints` as baseline; project may extend with `very_good_analysis`
- Pinned dependency versions in `pubspec.yaml` for production apps
- Never commit `.dart_tool/`, `build/`, or generated `.g.dart` files (except when checked-in intentionally)
