# SurgeWidget

The WidgetKit extension: one widget, "Surge", in Small, Medium and Large. It reads the snapshot
file the menu bar app writes and draws it. It never runs a pipeline, never imports `SurgeStateStore`
and never opens a socket.

## Where the data comes from

`SnapshotLocation` is the only place the path lives. It resolves the App Group container once the
entitlement exists, and `~/Library/Application Support/Surge/snapshot.json` until then. The app
writes that file; the widget only reads it. A missing, empty, corrupt or newer-schema file shows
the placeholder instead of failing.

## Layout rules that are not obvious

- Everything in the widget is at least 11 pt. Readouts use the Light readout tokens.
- Cards stay dark in both appearances, so the background is the card token inside
  `ContainerRelativeShape`.
- A stalled or idle row uses `Text(date, style: .timer)`, so the system keeps the elapsed label
  ticking between timeline reloads instead of the widget asking for one.
- Once the snapshot is more than five minutes old the widget says "Updated N min ago".
- Clicking anywhere opens `surge://panel`, with `?workspace=<id>` when the click has a workspace.

## Tests

The extension target has no test target and `project.yml` is outside this directory, so the pure
logic in `SurgeWidget/Logic/` is tested through the package next to it:

```sh
swift test --package-path Widget --scratch-path build/widget-tests
```

Keep the scratch path under `build/`, the repository's one build directory: it is gitignored and
excluded from `make lint`, so test scratch output never lands in the tree or the lint scan.

## Seeing it

```sh
make run
```

Then right-click the desktop, choose Edit Widgets, and add Surge. Small, Medium and Large are
supported, and the widget can be filtered to one project from its configuration.
