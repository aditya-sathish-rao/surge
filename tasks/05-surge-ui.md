# 05 - SurgeUI

Phase 2D. Starts after `core-v1`. Owns `Packages/SurgeUI` only. Branch: `feat/surge-ui`. Built and checked entirely against `SurgeCore` fixtures. No live pipeline needed.

Read: PRD sections 6, 7, 9. TRD sections 4, 13, 14. Design file sections "Layout", "Status system", "The Fuse", "Components", "Accessibility". Skills: `swiftui-pro`, `apple-design`.

## Goal

Every shared SwiftUI view: the Fuse, agent and sub-agent rows, pill tabs, workspace chips, charts, balances card, and the empty state. The popover, panel and widget all compose these. SurgeUI is the only package that implements visual components.

## Key requirements

- **The Fuse**: a capsule context meter with notches at 70 percent and 90 percent. White when normal, orange above 70, coral above 90, hatched when stalled so it reads in grayscale. A text label always sits beside it. Fixed 0 to 100 axis, never rescaled. Fill animates 0.3 s ease-out only when the value changes. Never pulses. Capsule is 6 pt in rows, 10 pt as a hero.
- **Agent row**: provider dot, state symbol, model name, tok/s or state word, then the Fuse and label. Minimum 44 pt tall. Sub-agents indented 16 pt with a hairline connector.
- **Popover content** is 360 pt wide, max 600 pt tall then scrolls. Tabs: Agents, Usage, Spend. Cards are opaque dark `#161617`. No custom glass.
- **Charts** (Swift Charts): 30-minute throughput, token totals by agent, context by agent, 14-day daily spend, spend by provider bar with legend, 7-day spend for the Large widget.
- **Empty state**: "No agents running" plus "Start Claude Code, or point workers at 127.0.0.1:8899."
- Colour rules: status owns orange and coral. Providers own lime, green, magenta, violet, only in dots and legends, never text. A healthy working agent is white.
- Accessibility: text at least 4.5:1, status graphics at least 3:1, nothing under 10 pt (11 pt in widgets). One VoiceOver element per row, for example "Claude Sonnet, orchestrator, surge-widget. Working, 68 tokens per second. Context 72 percent, high." Charts provide `AXChartDescriptor`. Reduce Motion cross-fades. Increase Contrast adds a 1 pt Fuse outline.

Fuse reference implementation (design file):

```swift
struct FuseGaugeStyle: GaugeStyle {
    var tripped = false
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            let v = configuration.value
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tripped ? AnyShapeStyle(HatchPattern(color: .surgeAlert))
                          : v >= 0.9 ? AnyShapeStyle(.surgeAlert)
                          : v >= 0.7 ? AnyShapeStyle(.surgeCaution)
                          : AnyShapeStyle(.surgeMeter))
                    .frame(width: geo.size.width * v)
                    .animation(.easeOut(duration: 0.3), value: v)
                ForEach([0.7, 0.9], id: \.self) { t in
                    Rectangle().fill(.background).frame(width: 1.5).offset(x: geo.size.width * t)
                }
            }
        }
        .frame(height: 6).clipShape(Capsule())
    }
}
```

## Business logic to test

Layout is checked by running the app. Test only the logic the views carry, as plain functions:

- Ratio to Fuse state (normal, high, near limit, tripped, idle, unknown) and its label text
- The VoiceOver sentence for a row from an `AgentNode`
- Sort and grouping helpers if any live here, and tab and chip count text
- Contrast: custom colour pairs meet 4.5:1 and 3:1 (compute from token values)

## Ask the user before deciding

- Colours and typeface are decided (see task 01). Use `SurgeCore` tokens, never hard-coded values.
- The sub-agent connector style, if the design file is unclear.
- Shared component changes after this task go through one named owner (TRD 15.1).

## Definition of done

Components render correctly in Xcode previews with fixture data in light and dark, with Increase Contrast and Reduce Motion, tests and lint pass, nothing outside the package touched.
