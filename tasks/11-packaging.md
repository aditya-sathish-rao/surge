# 11 - Packaging and distribution

Phase 7. One agent. Start after task 10 passes.

Read: PRD sections 10, 13. TRD sections 12, 16.

## Goal

Ship a notarized, non-sandboxed build the user can install.

## Requirements (TRD 12)

- Build a DMG and a Homebrew Cask formula. Both non-sandboxed, both notarized. Notarization does not need the sandbox.
- Document the non-sandboxed reason in the install instructions: Surge needs to read `~/.claude` and the local process table. Not on the Mac App Store.
- Fonts: if Beausite Classic is licensed, bundle the font files in **both** the app and the widget extension, each with its own `ATSApplicationFontsPath` in `Info.plist`, since the two bundles do not share resources. If not, ship Geist, which the app and widget already bundle, with only a font-mapping change in `SurgeCore` tokens.
- App Group entitlement shared by app and widget, scoped to the one snapshot container.
- App icon is a placeholder until the user supplies one.

## Ask the user before deciding

- Beausite Classic license: does it cover both bundles?
- Developer ID certificate and notarization credentials. The user provides them. Never store them in the repo.
- Where the DMG and Cask are hosted.

## Definition of done

A fresh Mac can install the DMG, Gatekeeper accepts it, and the widget appears in the gallery. Release steps are written down in plain English.
