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
- `jq`
- Hermes is optional; the panel reports when it is unavailable
- `hermes-node` is optional; federation disappears gracefully when unavailable

## Local development install

The repository directory must match the manifest ID:

```text
~/.config/omarchy/plugins/io.github.cody.hermes-harness
```

Then rescan and enable it:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.cody.hermes-harness
```

The widget defaults to the right bar section. Left-click opens the panel, middle-click refreshes, and right-click opens Hermes.

## Data sources

`scripts/hermes-status` reads the existing Omarchy Hermes usage record when available, then refreshes non-secret status from the installed `hermes`, the user gateway service, and `hermes-node`. It never writes Hermes state.

## Removal

Disable/remove the widget through Omarchy, then remove this user-local repository. No system rollback is necessary.
