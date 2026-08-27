# Hermes Harness for Omarchy

Hermes Harness is a user-local Quattro shell plugin for Omarchy. It adds a native bar indicator and panel showing:

- Hermes installed state and version
- gateway state
- active model
- current session
- federated node summary when `hermes-node` is available
- an **Open Hermes** action

The plugin is deliberately read-only. It does not install Hermes, alter gateway services, modify privileged interfaces, or change package-managed Omarchy files.

## Requirements

- Omarchy 4.x / current Quattro plugin runtime
- Python 3
- `jq`
- Hermes is optional; the panel reports when it is unavailable
- `hermes-node` is optional; federation disappears gracefully when unavailable

## Install

Install from the public repository and enable the widget:

```bash
omarchy plugin add https://github.com/archer-clawbot/omarchy-hermes-harness.git --enable
```

The widget defaults to the right bar section. Left-click opens the panel, middle-click refreshes, and right-click opens Hermes.

## Local development

The repository directory must match the manifest ID:

```text
~/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness
```

Saved changes hot-reload. Force discovery with `omarchy-shell shell rescanPlugins` when needed.

## Data sources

`scripts/hermes-status` reads the existing Omarchy Hermes usage record when available, then refreshes non-secret status from the installed `hermes`, the user gateway service, and `hermes-node`. Its I/O guard permits only bounded, descriptor-pinned regular-file reads and caps subprocess output before materialization. It never writes Hermes state.

## Documentation

- [Architecture](docs/architecture.md) — component boundaries and runtime flow
- [Security](docs/security.md) — permissions, trust boundaries, and non-goals
- [Telemetry](docs/telemetry.md) — status schema, sources, precedence, and freshness
- [Troubleshooting](docs/troubleshooting.md) — validation and recovery procedures
- [Agent skill](skill/SKILL.md) — bounded instructions for operating and maintaining this plugin

These documents cover the marketplace plugin itself. They do not install or document a privileged broker, Polkit policy, desktop-control bridge, distributed-job system, or package-managed Omarchy modification.

## Removal

```bash
omarchy plugin remove io.github.archer-clawbot.hermes-harness
```

No system rollback is necessary.
