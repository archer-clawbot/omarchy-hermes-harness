# Hermes Harness for Omarchy

Hermes Harness is a user-local Quattro shell plugin for Omarchy. It adds a native bar indicator and panel showing:

- Hermes installed state and version
- gateway state
- active model
- current session
- federated node summary when `hermes-node` is available
- whether Hermes is local or published from another host
- an **Open Hermes** action for a local install

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

The widget defaults to the right bar section. Left-click opens the panel, middle-click refreshes, and right-click opens Hermes. When the telemetry record says Hermes is remote there is no local executable to launch, so right-click opens the panel instead and the **Open Hermes** button is hidden.

## Local development

The repository directory must match the manifest ID:

```text
~/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness
```

Saved changes hot-reload. Force discovery with `omarchy-shell shell rescanPlugins` when needed.

## Data sources

`scripts/hermes-status` reads the existing Omarchy Hermes usage record when available, then refreshes non-secret status from the installed `hermes`, the user gateway service, and `hermes-node`. Its I/O guard permits only bounded, descriptor-pinned regular-file reads and caps subprocess output before materialization. It never writes Hermes state.

### Remote Hermes

If the record contains the exact JSON boolean `"remote": true`, Hermes is taken to be running on another host and refreshed into that record out of band. The record then supplies install, version, gateway, and node state, and no local probe runs at all.

Because remote mode suppresses local verification, the record is held to a strict contract: only real JSON booleans enable it, gateway values outside the known list fail closed to `unknown`, and freshness is decided by a local policy the record cannot widen. A record may ask for a shorter lifetime than the local maximum of 900 seconds but never a longer one, and a timestamp more than 120 seconds in the future is treated as stale rather than fresh. An expired record reports `gatewayState: "stale"` instead of a possibly long-dead `active`.

The record never carries a command, host, or URL, and the panel withholds its local launch actions in remote mode rather than running a `hermes` that is not installed. See [Telemetry](docs/telemetry.md) for the full contract and [Security](docs/security.md) for the trust boundary.

## Documentation

- [Architecture](docs/architecture.md) — component boundaries and runtime flow
- [Security](docs/security.md) — permissions, trust boundaries, and non-goals
- [Telemetry](docs/telemetry.md) — status schema, sources, precedence, and freshness
- [Troubleshooting](docs/troubleshooting.md) — validation and recovery procedures
- [Agent skill](skill/SKILL.md) — bounded instructions for operating and maintaining this plugin

These documents cover the marketplace plugin itself. They do not install or document a privileged broker, Polkit policy, desktop-control bridge, distributed-job system, or package-managed Omarchy modification.

## Tests

The status adapter has fixture-driven regression tests that run it against synthetic telemetry records in a sandboxed `HOME`, `XDG_STATE_HOME`, and `PATH`:

```bash
bash tests/run-tests.sh
```

They cover local mode, strict remote-mode typing, the freshness policy including stale, missing, forward-dated, and over-long-lived records, malformed node maps and counters, and proof that remote mode runs no local probe. GitHub Actions runs them along with shell, Python, and manifest syntax checks on every push and pull request.

## Removal

```bash
omarchy plugin remove io.github.archer-clawbot.hermes-harness
```

No system rollback is necessary.
