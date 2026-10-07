# iphone-duo-skill

A plugin for [Claude Code](https://claude.com/claude-code) and
[Codex](https://github.com/openai/codex) that helps adapt an existing iOS app
(SwiftUI or UIKit) to **iPhone Duo**, Apple's foldable iPhone.

It is a field guide distilled from adapting a real shipping SwiftUI app, covering:

- **Environment setup** — Xcode 27.1, iOS 27.1 runtime, DeviceHub
- **Static audit** — `scripts/audit_duo.sh` greps for risky patterns
- **Layout pitfalls on the inner display**, with tested fixes — `NavigationView` turning into a
  split view, orientation locks ignored, safe-area gaps, over-stretched controls
- **Simulator test matrix** — `scripts/duo_sim.sh` boots the Duo simulator and captures
  screenshots of the right display
- **App Store work** — Duo screenshot sizes, deadlines, featuring nomination

## Install

### Claude Code

```
/plugin marketplace add bones7456/iphone-duo-skill
/plugin install iphone-duo@iphone-duo-skill
```

### Codex

```
codex plugin marketplace add bones7456/iphone-duo-skill
codex plugin add iphone-duo@iphone-duo-skill
```

Tested with codex-cli 0.155.1, which reads the same `.claude-plugin/marketplace.json`.

### Usage

Then just ask, e.g. "get my app ready for iPhone Duo" or "帮我把这个 App 适配 iPhone Duo 折叠屏".
The skill is invoked as `iphone-duo:iphone-duo-adaptation`.

### Without the plugin system

Copy `plugins/iphone-duo/skills/iphone-duo-adaptation/` into:

- Claude Code: `~/.claude/skills/` (personal) or `<project>/.claude/skills/` (per project)
- Codex: `~/.codex/skills/`

## Update

Claude Code:

```
/plugin marketplace update iphone-duo-skill
```

Codex:

```
codex plugin marketplace upgrade iphone-duo-skill
```

## Caveats

Facts were verified on Xcode 27.1 RC (27A9275) with the iOS 27.1 simulator runtime in Oct 2026.
iPhone Duo and its tooling are new; re-check dates and sizes against Apple's current docs.
Corrections and issues are welcome.

## Layout

```
.claude-plugin/marketplace.json        # marketplace manifest
plugins/iphone-duo/
├── .claude-plugin/plugin.json         # plugin manifest
└── skills/iphone-duo-adaptation/
    ├── SKILL.md
    ├── references/swiftui-patterns.md
    └── scripts/{audit_duo.sh,duo_sim.sh}
```

## License

MIT
