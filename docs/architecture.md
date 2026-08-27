# Architecture

## Purpose

Hermes Harness is a native Omarchy Quattro bar widget and details panel for observing and opening a user-local Hermes installation. It is an adapter, not a Hermes installer or service manager.

The MVP exposes six facts:

1. whether `hermes` is available on `PATH`;
2. the first line of `hermes --version`;
3. the user gateway service state;
4. the configured active model;
5. the most recently published session metadata;
6. a bounded node-status summary when `hermes-node` exists.

## Component map

```text
Omarchy Quattro shell
└── BarWidget.qml
    ├── status glyph and pointer actions
    └── Loader
        └── Panel.qml
            ├── periodic refresh timer
            ├── scripts/hermes-status subprocess
            ├── JSON status model
            └── native KeyboardPanel UI

scripts/hermes-status
├── scripts/hermes-safe-io
│   ├── descriptor-safe bounded regular-file reads
│   └── time- and byte-bounded subprocess capture
├── command -v hermes
├── hermes --version
├── systemctl --user (read-only queries)
├── ~/.hermes/config.yaml (model only)
├── ~/.local/state/omarchy/agents/usage/hermes.json
└── hermes-node status (optional, bounded by timeout and output size)
```

## Quattro integration

The root `manifest.json` declares one `bar-widget` entry point. `BarWidget.qml` owns the bar slot and loads `Panel.qml` internally. The panel is intentionally not declared as a separate plugin kind.

`BarWidget.qml` forwards the panel lifecycle expected by Quattro:

- `opened`
- `open()`
- `close()`
- `toggle()`
- `closeForPopoutSwitch()`
- `popoutSwitchClosing`

It also injects the active bar, settings, anchor item, and host widget into the panel. This lets Quattro coordinate popouts and preserve keyboard navigation between neighboring bar panels.

## User interaction

| Input | Result |
|---|---|
| Left click | Toggle the Hermes panel |
| Middle click | Refresh status immediately |
| Right click | Launch `hermes` through the bar command runner |
| Escape | Close the panel |
| Panel navigation keys | Move to adjacent Quattro panels |
| Open Hermes button | Launch `hermes` and close the panel |

## Refresh lifecycle

The panel starts a refresh when it is created and repeats at the configured interval. The manifest default is 15 seconds and constrains settings to 10–300 seconds.

Only one status subprocess may run at a time. The panel parses completed stdout as one JSON object. A malformed response leaves the previous model visible and adds an error message instead of replacing known-good data with an empty state.

## Status precedence

The adapter begins with the existing Hermes provider record, when readable and valid. It then overwrites fields that can be checked cheaply and safely at refresh time:

1. live install detection and version;
2. live user gateway state;
3. model from the current Hermes config, falling back to the provider record;
4. live `hermes-node status`, falling back to the provider record only when no node lines are returned.

Session title and ID come from the existing provider record because MVP 1 does not inspect Hermes session databases or invent a noninteractive session API.

## Repository layout

```text
io.github.archer-clawbot.hermes-harness/
├── manifest.json
├── BarWidget.qml
├── Panel.qml
├── scripts/
│   ├── hermes-status
│   └── hermes-safe-io
├── docs/
│   ├── architecture.md
│   ├── security.md
│   ├── telemetry.md
│   └── troubleshooting.md
├── skill/
│   └── SKILL.md
├── README.md
└── LICENSE
```

## Explicit non-goals

This repository does not provide or modify:

- Hermes installation or updates;
- gateway installation, start, stop, or restart operations;
- Hyprland desktop-control commands;
- sudoers entries, Polkit policies, or privileged brokers;
- SSH keys or node configuration;
- remote command execution or capability routing;
- asynchronous or distributed jobs;
- Omarchy package files under `/usr` or `/usr/share/omarchy`.

Those capabilities require separate designs, authorization boundaries, and review. They must not be inferred from this status plugin.
