# Surge

A native macOS menu bar app and desktop widget that shows what your coding agents are doing right now: which ones are working, which are waiting on you, which have stalled, how full each context window is, how fast tokens are flowing, and what it has all cost today.

Surge is built for the pattern of one orchestrator (for example Claude Code) fanning work out to cheaper or specialised models over DeepSeek and OpenRouter. It watches all of them in one place so you do not have to tail logs or open three billing dashboards.

> Status: scaffolded. The Xcode project, package stubs and a placeholder menu bar item and widget build and run. No real features yet. See [Roadmap](#roadmap) and [`tasks/`](tasks/).

## Platform

Surge is a **macOS 14 (Sonoma) or later** app, written in Swift 6 and SwiftUI. It is not an iOS or iPadOS app. The PRD lists iOS, iPadOS and cross-device sync as non-goals for v1.0. It is distributed outside the Mac App Store because it needs direct access to `~/.claude` and the local process table, which the App Sandbox does not allow.

## What it shows

Every surface reads from the same state and the same design system.

| Surface | What it is |
| --- | --- |
| Menu bar item | A template glyph of up to four mini context meters for the busiest agents, with an optional short readout. Switches to an attention glyph the moment any agent needs you. Never animates. |
| Popover and panel | A 360pt dashboard with three tabs: Agents, Usage and Spend. Drag it off the menu bar to detach it as a floating panel. |
| Desktop widget | One widget, "Surge", in Small, Medium and Large. Small answers "is anything wrong?". Medium lists the four most urgent agents plus balances. Large shows the full agent tree, a 7-day spend chart and balances. |
| Notifications | Opt-in only, apart from "waiting for you" and an empty balance. Routine state never notifies. |

### Metrics

- Active agents and sub-agents, grouped by project workspace
- Token throughput: input, output and cache hit and miss
- Context window usage per agent, shown on the Fuse meter with markers at 70% and 90%
- Estimated spend per agent and workspace, calculated locally from a bundled pricing table
- Prepaid balance per provider account (DeepSeek and OpenRouter), polled every 60 seconds

### Agent states

Every agent is in exactly one state. Each state is carried by a symbol, a word and a meter treatment, so it reads without colour.

| State | Meaning |
| --- | --- |
| Working | Tokens flowing within the stall threshold (120s by default, configurable per model) |
| Waiting for you | Blocked on a permission prompt or a question |
| Stalled | No tokens for longer than the threshold and not waiting for you |
| Compacting | Context is being summarised |
| Idle | Session open, nothing requested |
| Done | Session ended normally, shown for 10 minutes |
| No signal | The proxy is down or logs are unreadable |

Sub-agents sit under their parent and never change the parent's state. Workspaces and agents that need attention always sort first.

## How it works

Three independent pipelines feed one in-process state store, which drives all three surfaces.

```
Claude Code  -> ~/.claude/projects/**/*.jsonl -> Pipeline A (transcript tailer)
Workers      -> 127.0.0.1:8899 (local proxy)  -> Pipeline B (pass-through proxy) -> DeepSeek / OpenRouter
Balance APIs <- poll every 60s                 -> Pipeline C (wallet poller)

Pipelines A, B, C -> SurgeStateStore (actor) -> menu bar and popover (live, in-process)
                                             -> App Group snapshot -> widget extension
```

- Menu bar and popover are fully live. They observe the state store directly, with no polling.
- The widget is a separate process with a system refresh budget. It only reads a small snapshot file the app writes to the shared App Group container. Snapshot writes are debounced to every 5 seconds and widget reloads to at most once a minute. Running timers such as "Stalled 3m 14s" tick on their own, and the widget says "Updated 2 min ago" when data is more than 5 minutes old.
- Point a worker at the proxy by setting its base URL, for example `OPENAI_BASE_URL=http://127.0.0.1:8899/deepseek` or `http://127.0.0.1:8899/openrouter`. The proxy forwards the worker's own credentials untouched and only reads the usage figures from the response.

### Swift packages

Each package is a hard compile boundary with its own tests.

| Package | Responsibility |
| --- | --- |
| `SurgeCore` | Domain models, design tokens, pricing table, formatting, cross-package protocols, sample fixtures |
| `SurgeIngestTailer` | Incremental parsing of Claude Code JSONL transcripts, sub-agent folder detection |
| `SurgeIngestProxy` | Local pass-through HTTP proxy, usage extraction, process-to-workspace linking |
| `SurgeWallets` | Balance polling for DeepSeek and OpenRouter, retry and backoff |
| `SurgeUI` | All shared SwiftUI views: the Fuse, agent rows, tabs, charts, balances card |
| `SurgeStateStore` | The actor that merges all pipelines, detects stalls, sorts and totals |
| `SurgeMenuBarApp` | App target: menu bar, settings, shortcut, notifications, snapshot writer |
| `SurgeWidget` | Widget extension target, reads the snapshot only |

## Privacy

- Prompt and response content is never written to disk. Only token counts, timestamps, model names and balances are stored, in `~/Library/Application Support/Surge/`.
- API keys live in the macOS Keychain only.
- The proxy binds to `127.0.0.1` and is never reachable from the network.
- The only outbound traffic is balance checks and the requests your workers were already making.

## Documentation

All product and engineering requirements live in [`docs/`](docs/). These files are read-only for every contributor and agent. See [Contributing](#contributing).

| File | Purpose |
| --- | --- |
| [`docs/Surge_PRD.docx`](docs/Surge_PRD.docx) | Product requirements: scope, behaviour, surfaces, definition of done |
| [`docs/Surge_TRD.docx`](docs/Surge_TRD.docx) | Technical requirements: architecture, packages, data model, testing, build plan |
| [`docs/surge-design-system.html`](docs/surge-design-system.html) | Visual and interaction reference |
| [`docs/surge.pdf`](docs/surge.pdf) | Original architecture blueprint |

Where documents disagree, the PRD wins. The TRD covers architecture where the PRD is silent, and the design file (v0.2) is the only visual and interaction reference. For example, the PRD allows a short text readout in the menu bar while the design file says one number, so the PRD applies.

## Roadmap

| Milestone | What becomes true |
| --- | --- |
| M1 Shell | The app runs in the menu bar and shows an agent tree from mock data, with the Fuse driven by the pricing table |
| M2 Claude visibility | Any Claude Code session appears live with correct tokens, context and estimated cost |
| M3 Worker visibility | DeepSeek and OpenRouter workers pointed at the proxy appear nested under the right workspace |
| M4 Money and widgets | Balances poll live and the widget works at all three sizes |

The TRD (section 15) breaks this into phases that let several agents build in parallel without touching the same files: scaffolding, the `SurgeCore` contract freeze, four parallel package streams, the state store, the app shell and widget, polish, hardening, and packaging.

## Development

### Requirements

- A Mac running macOS 14 or later
- Full Xcode (not only the command line tools), selected as the active developer directory
- Node.js, only to install the agent skills below
- XcodeGen, SwiftLint and swift-format: `brew install xcodegen swiftlint swift-format`

If `xcodebuild` reports that it requires Xcode, point it at the app:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Agent skills

Agents working in this repo follow these skills for Swift and design quality. Install them once per machine:

```sh
npx skills add dpearson2699/swift-ios-skills
npx skills add twostraws/swiftui-agent-skill --skill swiftui-pro
npx skills add dickwu/apple-design-skill
```

### Running the app

The Xcode project is generated from `project.yml` and is not committed. No simulator is needed.

From the terminal:

```sh
make run     # generate the project, build, and launch Surge
make stop    # quit it
```

The app has no Dock icon. Look for the bolt in the menu bar and click it to open the popover. It keeps running until you choose Quit Surge in the popover or run `make stop`.

From Xcode:

1. Run `make project`, then open `Surge.xcodeproj`.
2. Pick the `Surge` scheme and the `My Mac` destination, then press Run (Cmd+R).
3. Stopping the run in Xcode quits the app. To keep it running without Xcode open, use `make run`.

Signing defaults to "Sign to Run Locally", which is enough to run the menu bar app and see the widget in the widget gallery. Local development stays unsigned until the MVP. When you are ready for a signed build, add your Apple ID in Xcode (Settings, Accounts), then create `Config/Local.xcconfig` (not committed) with:

```
CODE_SIGN_STYLE = Automatic
DEVELOPMENT_TEAM = YOURTEAMID
```

Run `make project` again. The bundle ID prefix is `SURGE_BUNDLE_ID_PREFIX` in `Config/Base.xcconfig`. To add the widget, right-click the desktop, choose Edit Widgets, and add Surge.

Early milestones run on mock data, so you can watch the interface take shape before any live ingestion exists.

### Fonts

The app and widget bundle the variable Geist Sans font (SIL Open Font License 1.1, from [vercel/geist-font](https://github.com/vercel/geist-font)) and Fira Code (SIL Open Font License 1.1, from [tonsky/FiraCode](https://github.com/tonsky/FiraCode)). Each licence text ships next to its font in `App/SurgeMenuBarApp/Fonts/` and `Widget/SurgeWidget/Fonts/`.

### Tests and checks

```sh
make test    # run the tests of every package
make lint    # SwiftLint and swift-format, zero warnings allowed
make format  # apply swift-format
```

## Contributing

The full rules are in [`AGENTS.md`](AGENTS.md). In short:

- `docs/` is read-only. Never edit the PRD, TRD, design file or blueprint. If they are unclear or wrong, stop and ask.
- One package, one owner, one branch. A change touches one package and its tests. Frozen public APIs are additive only.
- Test business logic through public behaviour, not code structure.
- Commit messages are short, plain English about what changed and why. No co-author lines, no tool attribution.
- Code must follow the three skills above and pass lint with no warnings.
