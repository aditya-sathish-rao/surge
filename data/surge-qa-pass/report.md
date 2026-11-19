# Surge end to end QA pass

Run on 19 November 2026 against a debug build of `Surge.app` on this Mac, with the app started
from the terminal (`open build/Build/Products/Debug/Surge.app`). The proxy was exercised with real
DeepSeek traffic sent by `curl` from a real working directory, using the DeepSeek key already in
the shell environment. No key was written anywhere, no transcript was faked, and no workaround was
added for the widget.

Every check below is pass, fail, or not exercisable with the reason.

## 1. A worker pointed at the proxy

**Pass, with two caveats.**

- A real request sent to `http://127.0.0.1:8899/deepseek/chat/completions` passed through to
  DeepSeek and came back with HTTP 200 and a real completion.
- The worker appeared in the app within about one second of the request: measured from request
  start to the first snapshot containing it, 0.86s, 0.81s and 0.96s across three runs. The
  snapshot is written immediately for the first change and coalesced to five seconds after that.
- It landed under the right workspace: `surge`, the working directory of the process that made the
  request, with the full path shown.
- Usage arrived: 10 input and 2 output tokens, then 11 and 3 on the next run. The row reads the
  model as `DeepSeek Flash`, taken from the model the response reported (`deepseek-flash`). The row
  expanded in the detached panel shows `Tokens 10 in · 3 out · 0 cache`, the session ID and the
  working directory.
- Caveat one: no Claude session was live on this machine, so the worker is promoted to the
  workspace's top level agent instead of nesting under an orchestrator. That is the documented rule
  in `StoreDerivation.orchestrator(in:)`, not a defect, but it means the menu bar read
  `1 Orch, 0 Workers, $0.00` for one worker process. The Claude half of this check cannot be
  exercised here: no Claude CLI is installed and the newest transcript is a day old.
- Caveat two: the exact model ID never appears in the UI. The row shows a friendly name derived
  from the ID and the expanded detail shows tokens, session ID and working directory only.
- The context window reads 0% of 128,000 while the live model reports 1,048,576. See finding 1.

## 2. Today's spend and the balances update on their own

**Fail for spend, not exercisable for two of three balances.**

- No manual refresh exists anywhere in the UI. The only controls are Pause Monitoring, Settings and
  Quit. The wallet poller runs on its own: the `lastPolledAt` timestamps in the snapshot advance
  every 60 seconds without any interaction.
- Today's spend stayed `$0.00` through three real requests, and the 14 day chart and the spend by
  provider card stayed empty. The cause is finding 1: the bundled pricing table has no entry for
  the model IDs DeepSeek returns today, so the recorded cost is zero.
- Anthropic: **unavailable by design**, it exposes no balance endpoint, so it always reads
  "Balance unavailable".
- DeepSeek: **unavailable**. There is no key under the `com.surge.apikeys` Keychain service and the
  app has no screen that asks for one, so this will be unavailable for every user until a key entry
  screen exists. The path itself works: called directly with the key from the environment,
  `GET https://api.deepseek.com/user/balance` answered
  `{"is_available":true,...,"total_balance":"24.37"}`, which is exactly the shape
  `DeepSeekBalanceParser` decodes, so a stored key would show $24.37.
- OpenRouter: **not exercisable**. There is no OpenRouter key on this machine.

## 3. The privacy floor

**Pass.**

- `~/Library/Application Support/Surge/` holds one file, `snapshot.json`, with `schemaVersion`,
  `generatedAt`, `workspaces` (agent id, provider, model, status, token counts, context figures,
  estimated cost, timestamps, project path), `balances` and `dailySpend`. Nothing else.
- Searching the same directory and the widget's container for the exact prompt and response text
  that were sent (`latency probe`, `hello worker`) returns nothing.
- The app's preferences hold a window frame and one stall threshold override, both user settings.
- The widget's container has no snapshot, so the widget has nothing to read until the App Group
  exists. Nothing prompt or response shaped is in it.

## 4. The degraded paths

**Partial. Nothing crashes, but the app never says "No signal".**

- With port 8899 already held by another process, the app started, kept running and showed the
  empty state. No crash, no error dialog.
- It did **not** show "No signal" or any reason. `ProxyUnavailableReason.reasonText` exists and
  would read "Port 8899 is already in use.", but no surface reads the proxy's state: neither the
  menu bar, the popover, the panel nor the widget observes it, and nothing turns a failed listener
  into a "No signal" agent state. See finding 2.
- After the other process released the port, the app did not retry the bind. The proxy stayed down
  until the app was relaunched, and nothing on screen said so.
- Starting with no agents shows the empty state: `> no agents running_` and
  "Start Claude Code, or point workers at 127.0.0.1:8899."
- Bind check: `lsof -nP -iTCP:8899` shows one listener, `127.0.0.1:8899`. It never binds to the
  wide address, so it is not reachable from another machine on the network.

## 5. The menu bar item, popover, panel and settings, light and dark

**Pass with findings; two things look broken.**

Checked in light and in dark appearance, by looking at the running app and at screenshots.

- Menu bar item: a glass pill with a bolt, then `1 Orch, 0 Workers, $0.00`. Readable in both
  appearances, no animation, and it switched to the warning triangle with the count when the agent
  stalled. The menu bar is mostly off screen on this machine until the pointer reaches the top
  edge, which is a display arrangement here and not an app problem.
- Popover and panel: the same dashboard, the panel adds a title bar. Cards stay dark in both
  appearances, as designed. The workspace header, agent row, Fuse with its 70% and 90% marks, the
  provider column and the balances card all draw correctly. The stalled agent showed the warning
  symbol, the word `Stalled 2m 22s` and the red row tint.
- A blue focus ring is drawn around the whole tab control on every surface and in both
  appearances. It looks like a stray focus ring rather than a designed state.
- In the popover, clicking an agent row does nothing, so the tokens, session ID and working
  directory detail cannot be opened. The identical row expands correctly in the detached panel,
  which points at the menu bar popover window rather than at the row code. VoiceOver can only get
  the row's context menu, so the detail is unreachable with a keyboard or VoiceOver too.
- Settings: in light appearance the explanatory captions were almost invisible before this pass,
  and are readable now (fixed here). In dark appearance they were always fine.
- Small copy and layout points for the polish pass: `1 need you` in the header, `All agents working`
  when no agent exists, "100% below your 30-minute average" when both numbers are zero, two
  identical `12:00 PM` labels on the usage chart, uppercase section labels, and the white window
  chrome around dark cards in light appearance.
- Widget: **not exercisable**. The extension is not registered with WidgetKit on this machine
  (`pluginkit` lists no Surge widget extension), so it cannot be added to the desktop, and without
  the App Group entitlement it reads the snapshot inside its own sandboxed container, where no
  snapshot exists. It shows its placeholder by design until packaging adds the App Group.

## Findings

1. **The pricing table is stale against the real DeepSeek API.** Today the API lists
   `deepseek-flash` (1,048,576 context) and `deepseek-v4-pro`; a `deepseek-chat` request answers
   with model `deepseek-flash`. The bundled table only knows `deepseek-chat` and
   `deepseek-reasoner`, so `estimatedCostUSD` returns nil, the store records 0, and today's spend
   never moves for real worker traffic. The same gap leaves the context window at 128,000, taken
   from the request's model name at announce time, while the model's real window is 1,048,576.
   Fixing this needs the real prices for the current models, which is a product decision.
2. **Nothing surfaces "No signal" or a reason.** The proxy's state and its plain English reason
   exist in `SurgeIngestProxy` and are never read by any surface, and no pipeline can put an agent
   into the `noSignal` state. A failed listener therefore looks exactly like "no agents running",
   and the proxy never retries the bind, so the only recovery is to relaunch the app.
3. **The agent row cannot be opened in the menu bar popover.** It expands in the panel, not in the
   popover, so tokens, session ID and working directory are inaccessible from the menu bar. Needs
   a menu bar popover specific interaction fix.
4. **Balances cannot be configured.** The app reads provider keys from the Keychain under
   `com.surge.apikeys` but has no screen that asks for one, so both key backed balances are
   permanently unavailable for a normal user.
5. **The menu bar counts a worker as an orchestrator** when no Claude session is present. That is
   the documented promotion rule, but the readout then says `1 Orch, 0 Workers`, which misreports
   what is running.

## Fixed in this pass

Small, clear defects, each verified in the rebuilt app:

- Settings captions were unreadable in light appearance because they used the dark card ink
  tokens on a system form background; they now use the system secondary colour.
- The VoiceOver sentence said "1 agents need you" and "Surge. 1 agents, 1 need you."; both now
  read singular for one agent. The dashboard label was checked live: after the agent stalled it read
  "1 agent needs you". The menu bar readout uses the same one line rule and was not read back
  through VoiceOver here.
- A model ID with a dotted version, `claude-sonnet-5-5`, read as "Claude Sonnet 5 5" in Settings
  and in rows; it now reads "Claude Sonnet 5.5", with a test.

## What was not exercisable, and why

- A live Claude session in the menu bar: no Claude CLI on this machine, newest transcript is a day
  old. No transcript data was invented to force it.
- OpenRouter spend and balance: no OpenRouter key here.
- DeepSeek balance showing an amount: no key in the Keychain, and adding one would mean writing a
  key, which this pass does not do.
- The widget on the desktop and at all three sizes: the extension is not registered with WidgetKit
  and it has no App Group to read from.
