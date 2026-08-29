# Telemetry contract

## Overview

`scripts/hermes-status` writes exactly one JSON object to stdout. `Panel.qml` treats that object as display-only status.

The output is intentionally compatible with an existing Omarchy Hermes provider record: unknown fields from that record are preserved, while the adapter refreshes the MVP fields it owns.

## Core fields

| Field | Type | Source | Meaning |
|---|---|---|---|
| `installed` | boolean | `command -v hermes`, or the record in remote mode | Hermes is available to this panel |
| `version` | string | first line of `hermes --version`, or the record in remote mode | Human-readable Hermes version, capped at 512 characters |
| `gatewayState` | string | `systemctl --user`, or the record in remote mode | `active`, `stopped`, `not-installed`, `stale`, or `unknown` |
| `activeModel` | string | Hermes config, then base record | Configured model identifier, capped at 256 characters |
| `currentSessionId` | string | base record | Published session identifier |
| `currentSessionTitle` | string | base record | Published session/task label |
| `hermesNodeAvailable` | boolean | `command -v hermes-node`, or the record in remote mode | Optional node wrapper exists |
| `nodesOnline` | integer | live node status or base record | Online-node count, 0 to 65536 |
| `nodesTotal` | integer | live node status or base record | Known-node count, 0 to 65536 |
| `nodes` | object | live node status or base record | Validated map keyed by node alias |
| `remote` | boolean | base record, strict JSON `true` only | Hermes runs on another host |
| `remoteStale` | boolean | local freshness policy | The remote record is past its permitted lifetime |
| `staleAfterSec` | integer | local policy, clamped from the record | Effective record lifetime; emitted in remote mode only |

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

## Remote records

A publisher may run Hermes on another host and refresh this record out of band. Local probes cannot see that install, so in remote mode the record is authoritative for `installed`, `version`, `gatewayState`, `hermesNodeAvailable`, and the node summary.

Remote mode is entered only for the exact JSON boolean:

```json
{ "remote": true }
```

Any other value, including the string `"true"`, `1`, `null`, or an object, leaves the adapter in local mode. Remote mode suppresses local verification, so it must not be reachable by a value that merely looks true.

### Accepted types in remote mode

| Record field | Accepted | Anything else |
|---|---|---|
| `remote` | JSON `true` | local mode |
| `installed` | JSON `true` | `false` |
| `hermesNodeAvailable` | JSON `true` | `false` |
| `gatewayState` | `active`, `stopped`, `not-installed`, `unknown` | `unknown` |
| `collectedAtEpoch` | finite number, floored, 0 to 4102444800 | treated as absent, so the record is stale |
| `staleAfterSec` | finite number, floored, clamped to 1 to 900 | local default of 300 |
| `nodes` | object whose keys match `[A-Za-z0-9._-]{1,64}` and whose values are objects | entry dropped, or the whole map replaced by `{}` |
| `nodesOnline`, `nodesTotal` | finite number, floored, clamped to 0 to 65536 | count derived from the validated node map |

`nodesOnline` is additionally clamped to `nodesTotal`.

### Node-probe suppression

In remote mode the adapter runs no local probe. It does not resolve `hermes` or `hermes-node` on `PATH`, does not execute `hermes --version`, does not query `systemctl --user`, and does not read the Hermes configuration. `tests/run-tests.sh` asserts this by putting recording stubs on `PATH` and requiring that none of them is invoked.

### Freshness policy

Freshness is decided by this adapter, never by the record it is judging:

- the longest lifetime a record may have is a local maximum of 900 seconds; a record asking for more is clamped down to it, so no record can declare itself fresh for a year;
- the default lifetime, used whenever the record supplies nothing usable, is 300 seconds;
- a record is stale once `now - collectedAtEpoch >= staleAfterSec`, so expiry is inclusive at the boundary;
- a missing, non-numeric, zero, or negative `collectedAtEpoch` is stale;
- a `collectedAtEpoch` more than 120 seconds in the future is stale, so a forward-dated record cannot buy itself time;
- every value is floored and clamped before it reaches shell arithmetic, so a non-numeric, negative, or absurdly large number cannot break or extend the check.

The effective lifetime is republished as `staleAfterSec`, so the output shows the policy value actually applied rather than the value the record asked for.

A stale record reports `remoteStale: true` and `gatewayState: "stale"`. Its `installed`, `version`, and `activeModel` values are still displayed, because a dead publisher is not evidence that Hermes was uninstalled, but an expired record can never report an `active` gateway.

### Panel behaviour in remote mode

The panel shows a **Hermes host** row reading `local`, `remote (published record)`, or `remote (record expired)`. Because a remote Hermes has no local executable:

- the **Open Hermes** button is hidden and replaced by a short explanation;
- bar right-click opens the panel instead of running `hermes`.

The record never supplies a command, URL, or launch target. Adding a record-controlled launch action would require its own security review.

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

In remote mode the state comes from the record instead, restricted to the same four values, and becomes `stale` whenever the record is outside the local freshness policy. `stale` therefore means "no current statement about the gateway", not "the gateway is down".

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

A node map that comes from the record rather than from a live probe is validated the same way before use: `nodes` must be an object, each key must match the alias pattern, each value must be an object, `online` is reduced to a strict boolean, and at most 256 entries are carried through. A `nodes` value of the wrong type becomes `{}` rather than contributing a length; published counters are floored, clamped, and fall back to counts derived from the validated map.

## Freshness and interpretation

The default panel refresh period is 15 seconds, but data can still be stale:

- the base record is produced elsewhere;
- a remote record is only as current as its publisher, which is why the freshness policy above is enforced locally;
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
       currentSessionTitle, hermesNodeAvailable, nodesOnline, nodesTotal, nodes,
       remote, remoteStale}'
```
