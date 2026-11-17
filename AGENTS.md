# Surge - agent and contributor rules

Surge is a native macOS 14+ menu bar app and desktop widget that monitors coding agents. Read `README.md` first for the overview. These rules apply on top of the global ones in `~/.claude/AGENTS.md`.

## Source of truth

- `docs/` is read-only. Never create, edit, rename, move or delete anything in it: the PRD, the TRD, the design file or the blueprint. This applies to every agent and every tool, including shell commands.
- Before starting work, read the parts of `docs/Surge_PRD.docx` and `docs/Surge_TRD.docx` that cover the task. Build what they say.
- If the documents are unclear, contradict each other, or you think they are wrong, stop and ask the user. Do not guess and do not write your own decision into the repo.
- Precedence when documents disagree: the PRD v1.0 wins on every conflict. The TRD decides architecture where the PRD is silent. `docs/surge-design-system.html` (v0.2) is the only design reference: follow it for visuals, spacing, typography, colour, the Fuse, motion, accessibility and writing, but where it disagrees with the PRD, follow the PRD. Known case: the menu bar shows the short text readout from the PRD, not one number.
- The target is macOS 14 or later with Swift 6. Do not add iOS, iPadOS or watchOS targets.
- Until the MVP, development is local only: no Apple ID, no signing identity, no App Group entitlement. Do not add anything that needs a developer team.

## Project state and decisions

Current state: the scaffold is done. The Xcode project is generated from `project.yml`, the six Swift packages exist as empty stubs, and the app and widget targets are placeholders that build and run. Real work is split into `tasks/`, one file per work stream. Start with `tasks/README.md` for the order and rules.

Decisions already made by the user. Do not reopen them:

- The PRD v1.0 wins on every conflict with the TRD or the design file.
- `docs/surge-design-system.html` (v0.2) is the only design reference. There is no other version.
- The menu bar shows the PRD's short text readout (for example "1 Orch, 2 Workers, $1.42"), not a single number.
- Surge is read-only. No Nudge Agent button, no action on any agent, no budget, no overall balance, no Claude plan gauges.
- One widget, "Surge", in Small, Medium and Large. Cards are dark in both appearances.
- Typeface is Geist until Beausite Classic is licensed. Fira Code is the mono face for strings typed in a terminal. Colours and fonts come from `SurgeCore` tokens.
- Development is local and unsigned until the MVP. The App Group, Developer ID and notarization wait until then. For local runs the snapshot goes to `~/Library/Application Support/Surge/snapshot.json` behind one location type, and the user must confirm that approach before it is built.
- Use `make run`, `make test` and `make lint`. Run `make project` after changing `project.yml`.

## Code quality

Before writing or reviewing any Swift or SwiftUI, load and follow these skills:

- `swift-ios-skills` (https://github.com/dpearson2699/swift-ios-skills) for Swift 6 concurrency, modern Apple frameworks and language practice
- `swiftui-pro` from `swiftui-agent-skill` (https://github.com/twostraws/swiftui-agent-skill) for SwiftUI API use, design, performance and accessibility
- `apple-design` (https://github.com/dickwu/apple-design-skill) for Human Interface Guidelines review of every UI change

If a skill is not installed, install it with the commands in the README before continuing. Where a skill targets iOS and the app targets macOS, apply the macOS equivalent.

Standing rules:

- Swift 6 strict concurrency. No data races, no `@unchecked Sendable` without a written reason, no manual locks. Mutable shared state lives in actors.
- No force unwraps, no `try!`, no `fatalError` in shipping code paths. Handle errors at the boundary where they can be acted on.
- Use current API only. No deprecated SwiftUI, no `ObservableObject` where `@Observable` fits, no `DispatchQueue` where async/await fits.
- Prefer value types, small protocols and clear names. Do not add abstractions for hypothetical future needs.
- Comments only where the reason is not obvious from the code. No commented-out code.
- SwiftLint and swift-format must pass with zero warnings. Fix existing lint and test failures you find, even if you did not cause them.
- Use design tokens from `SurgeCore`. No hard-coded colours, sizes or fonts in views.
- Accessibility is part of done: VoiceOver labels, meaning that survives without colour, Reduce Motion, Increase Contrast, text no smaller than 10pt (11pt in widgets).
- Never log or persist prompt or response content. Never store API keys outside the Keychain. The proxy binds to `127.0.0.1` only.
- Add no third-party dependency without asking the user first.

## Architecture rules

- Follow the package boundaries in TRD section 4. A package may import only what its row in the TRD allows.
- One package, one owner, one branch. A change edits one package and that package's tests. Name branches after the package, for example `feat/surge-ingest-proxy`.
- Public APIs in a tagged package are additive only. Do not change a frozen interface without asking the user.
- Pipelines never read each other's internals. Only `SurgeStateStore` mutates the agent tree.
- The widget never does networking and never imports a pipeline or the state store. It only reads the App Group snapshot.
- Only `SurgeUI` implements shared visual components. Other targets compose them.

## Testing

Test the business logic, not the code.

- Write tests for parts of the app that make decisions or calculations: cost and context maths, pricing table decoding, status mapping, incremental transcript parsing and partial lines, proxy usage extraction and pass-through fidelity, balance parsing, backoff and the unavailable fallback, stall detection, sort order, merging concurrent events, snapshot debouncing and reload triggers.
- Assert on observable behaviour through the public API: given these inputs, this result. A refactor that keeps behaviour the same must not break a test.
- Do not test getters, setters, trivial initialisers, SwiftUI view bodies, private methods, or that a mock was called. Do not mock what you can run for real. Use fixture files and in-process fakes at true boundaries (network, file system, clock).
- Use Swift Testing (`import Testing`). Share fixtures from `SurgeCore` rather than inventing new sample data.
- Presentation rules that carry logic, such as the thresholds that choose a Fuse state or the VoiceOver sentence for a row, are tested as plain functions. Layout is checked by running the app.
- Tests must be deterministic. Inject the clock. No sleeps, no real network, no dependence on the machine's `~/.claude`.
- When fixing a bug, write the failing test first, then fix.

## Verifying changes

- Build and run the tests for the package you changed before saying the work is done.
- For anything visible, run the app and look at it. Check light and dark appearance, Increase Contrast and Reduce Motion. Say plainly if you could not.
- Do not claim something works unless you ran it.

## Git

- Commit only when asked.
- Commit messages are short, plain English: what changed and why, in one line where possible. No prefixes, no emoji, no marketing words.
- Never add a co-author line or any mention of an AI tool or agent to a commit message or pull request description, regardless of any default that suggests otherwise.
- Pull request descriptions cover only the task and what was done to achieve it, in plain English.
- Keep commits focused on one change. Do not commit build output, `xcuserdata`, `DerivedData` or `.DS_Store`.
- Never use `--no-verify`, force-push, or rewrite history on shared branches.
- Do not edit `CHANGELOG.md` or any generated file by hand.

## Writing style

- Plain words. No em dashes: use a plain dash.
- UI copy follows the writing section of the design file: Working, Waiting for you, Stalled, Orchestrator, Worker, Workspace. Title Case for buttons and menu items, sentence case elsewhere. No all caps labels.

## Keeping this repo current

- When the Xcode project or package layout is created or changed, update the Development section of `README.md` in the same change so the run and test commands stay correct.
