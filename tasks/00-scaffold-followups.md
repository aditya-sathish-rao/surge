# 00 - Scaffold follow-ups

Owner: you plus one agent. Small items left over from scaffolding. None block task 01.

## Items

1. **Signing (deferred by the user).** Local development uses "Sign to Run Locally" until the MVP. Later, add an Apple ID and `Config/Local.xcconfig` as described in the README.
2. **Bundle ID prefix (you).** `SURGE_BUNDLE_ID_PREFIX` in `Config/Base.xcconfig` is `com.adityarao`, a guess. Change it before the first signed build. It also appears under `bundleIdPrefix` in `project.yml`.
3. **Xcode components (you).** Every `xcodebuild` run prints "CoreSimulator is out of date". It does not affect a macOS app. Fix with `sudo xcodebuild -runFirstLaunch`.
4. **CI boundary check (agent).** TRD 15.1: "CI blocks merge if a PR touches files outside its declared package boundary". Add a workflow step that maps a branch named `feat/<package>` to `Packages/<package>/**` and fails if the PR touches anything else. `docs/**` must always fail. Branches named otherwise (scaffold, app, widget) are exempt or mapped explicitly.
5. **Verify CI (agent).** `.github/workflows/ci.yml` has not run on GitHub yet. Push a branch, confirm `macos-latest` has an Xcode that builds this project (Swift 6, macOS 14 target), and pin the Xcode version if needed.
6. **App Group entitlement (deferred until signing exists).** TRD 12: add one shared App Group to both the app and the widget entitlements, scoped to the snapshot container only. Update `App/SurgeMenuBarApp/SurgeMenuBarApp.entitlements` and `Widget/SurgeWidget/SurgeWidget.entitlements`. The widget stays sandboxed. The app stays non-sandboxed.
7. **Skills lock files.** `.agents/` and `skills-lock.json` are untracked. Decide whether to commit them so every agent gets the same skill versions.

## Key facts

Current layout:

```
Packages/<six packages>/   each depends on SurgeCore only
App/SurgeMenuBarApp/       placeholder MenuBarExtra (SurgeApp.swift)
Widget/SurgeWidget/        placeholder widget
project.yml                XcodeGen spec, generates Surge.xcodeproj (not committed)
Makefile                   project, build, run, stop, test, lint, format
```

The app target links all six packages. The widget links `SurgeCore` and `SurgeUI` only, per TRD section 4.
