# Telemetry contract

## Overview

`scripts/hermes-status` writes exactly one JSON object to stdout. `Panel.qml` treats that object as display-only status.

The output is intentionally compatible with an existing Omarchy Hermes provider record: unknown fields from that record are preserved, while the adapter refreshes the MVP fields it owns.

## Core fields

| Field | Type | Source | Meaning |
|---|---|---|---|
| `installed` | boolean | `command -v hermes` | Hermes executable is discoverable |
| `version` | string | first line of `hermes --version` | Human-readable Hermes version |
| `gatewayState` | string | `systemctl --user` | `active`, `stopped`, `not-installed`, or `unknown` |
| `activeModel` | string | Hermes config, then base record | Configured model identifier |
| `currentSessionId` | string | base record | Published session identifier |
| `currentSessionTitle` | string | base record | Published session/task label |
| `hermesNodeAvailable` | boolean | `command -v hermes-node` | Optional node wrapper exists |
| `nodesOnline` | integer | live node status or base record | Online-node count |
| `nodesTotal` | integer | live node status or base record | Known-node count |
| `nodes` | object | live node status or base record | Map keyed by node alias |

Each live node entry currently has this minimal shape:

```json
{
  "online": true
}
```

Additional fields present in an existing provider record may disappear from a node when live `hermes-node status` replaces the cached node map. Consumers must not depend on hostnames, load, GPU, or uptime fields in this MVP contract.

## Existing provider record

The optional base file is:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/hermes.json
```

This plugin does not create or update that file. Another integration may publish fields such as token usage, provider, session status, detailed node telemetry, or usage history. The adapter carries them through when valid, but the plugin UI uses only the core fields above.

## Gateway states

Gateway detection is intentionally based on the user service manager rather than parsing human-formatted `hermes gateway status` output.

```text
systemctl --user is-active hermes-gateway.service
  success → active

systemctl --user is-enabled hermes-gateway.service
  success → stopped

otherwise → not-installed
```

If Hermes itself is missing, the initial state remains `unknown`.

`not-installed` means the expected user unit was not reported as enabled; it is not proof that no alternate gateway process exists.

## Model parsing

The adapter reads a top-level line whose key is exactly `model` from:

```text
${HERMES_HOME:-$HOME/.hermes}/config.yaml
```

It removes double quotes from the value. If no model is found, it falls back to `activeModel` from the provider record. This is a deliberately narrow parser, not a general YAML implementation.

## Node collection

When `hermes-node` exists, the adapter invokes it through the bounded I/O guard with:

```bash
hermes-safe-io run 18 65536 -- hermes-node status
```

It accepts lines matching:

```text
<node-alias>: online
<node-alias>: offline
```

Other output is ignored. If at least one matching line is returned, that live set replaces the cached node map. If no lines match, the adapter falls back to cached `nodes`, `nodesOnline`, and `nodesTotal` values.

The 18-second outer timeout and 64 KiB output ceiling bound the aggregate status call before output reaches a shell variable. Node aliases must match `[A-Za-z0-9._-]{1,64}`. Any timeout internal to `hermes-node` remains the responsibility of that command.

## Freshness and interpretation

The default panel refresh period is 15 seconds, but data can still be stale:

- the base record is produced elsewhere;
- a node fallback may reuse earlier values;
- session fields are not independently refreshed;
- a command may finish just before external state changes.

The UI is an operational summary, not an audit log or health guarantee.

## Manual inspection

Run the adapter directly:

```bash
~/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness/scripts/hermes-status | jq .
```

Inspect only the MVP contract:

```bash
~/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness/scripts/hermes-status |
  jq '{installed, version, gatewayState, activeModel, currentSessionId,
       currentSessionTitle, hermesNodeAvailable, nodesOnline, nodesTotal, nodes}'
```
