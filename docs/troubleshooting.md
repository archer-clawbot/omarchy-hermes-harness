# Troubleshooting

## Safe diagnostic sequence

Set the plugin path once:

```bash
PLUGIN_ID=io.github.archer-clawbot.hermes-harness
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
```

Then work from the cheapest check to the broadest:

```bash
omarchy plugin validate "$PLUGIN_DIR"
bash -n "$PLUGIN_DIR/scripts/hermes-status"
python3 -m py_compile "$PLUGIN_DIR/scripts/hermes-safe-io"
"$PLUGIN_DIR/scripts/hermes-status" | jq .
bash "$PLUGIN_DIR/tests/run-tests.sh"
omarchy-shell shell rescanPlugins
omarchy-shell shell ping
omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
```

## Plugin is not listed

Confirm the directory and manifest ID match exactly:

```text
~/.config/omarchy/plugins/io.github.archer-clawbot.hermes-harness
```

```bash
jq -r .id "$PLUGIN_DIR/manifest.json"
omarchy plugin validate "$PLUGIN_DIR"
omarchy-shell shell rescanPlugins
```

Third-party IDs must not start with `omarchy.`. The plugin directory must not contain symlinks.

## Plugin is listed but absent from the bar

Inspect enabled state:

```bash
omarchy plugin list --json | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
```

Enable it if needed:

```bash
omarchy plugin enable "$PLUGIN_ID"
```

Move it explicitly if desired:

```bash
omarchy bar move "$PLUGIN_ID" --section right
```

## Panel does not open

Exercise the Quattro lifecycle directly:

```bash
omarchy-shell shell summon "$PLUGIN_ID" '{}'
omarchy-shell shell hide "$PLUGIN_ID"
```

Inspect recent QML output:

```bash
qs log -p "$OMARCHY_PATH/shell" --tail 100
```

If hot reload preserved a stale component, perform one clean user-shell restart:

```bash
omarchy restart shell
omarchy-shell shell ping
```

Do not edit or replace files under `/usr/share/omarchy`.

## Hermes reports not installed

Check the same executable resolution available to the shell:

```bash
command -v hermes
hermes --version
```

This plugin does not install or repair Hermes. Fix the user environment or Hermes installation separately, then refresh the widget.

## Panel shows a remote Hermes

Check what the record actually claims:

```bash
jq '{remote, collectedAtEpoch, staleAfterSec, installed, gatewayState}' \
  "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/hermes.json"
```

Remote mode requires the exact JSON boolean `true`. A string `"true"` leaves the plugin in local mode, which is intentional. In remote mode no local probe runs, so `command -v hermes` on this host is irrelevant, and the local launch actions are withheld because there is nothing local to launch.

## Gateway state is stale

`stale` means the remote record is outside the plugin's local freshness policy: the timestamp is missing, non-numeric, older than the record's effective lifetime, or more than 120 seconds in the future. It is not a statement about the gateway.

```bash
jq '{collectedAtEpoch, staleAfterSec}' \
  "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/hermes.json"
date +%s
```

Fix the publisher that writes the record, or fix clock skew between the hosts. The record cannot ask for a lifetime beyond the local maximum of 900 seconds, and that maximum must not be widened to hide a dead publisher.

## Gateway state looks wrong

Query the expected user unit directly:

```bash
systemctl --user is-active hermes-gateway.service
systemctl --user is-enabled hermes-gateway.service
```

The plugin never starts, stops, installs, or refreshes the unit. A gateway managed by another unit name or process will not be detected by MVP 1.

## Model is unknown

Check whether the narrow parser can see a top-level `model` key:

```bash
awk -F': *' '$1 == "model" { print $2; exit }' "${HERMES_HOME:-$HOME/.hermes}/config.yaml"
```

If the model is stored in a different structure, the adapter falls back to the existing provider record. Do not broaden parsing in a way that prints secret-bearing configuration.

## Session is missing or stale

Session metadata is inherited from:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/hermes.json
```

Validate it without displaying unrelated contents:

```bash
jq '{currentSessionId, currentSessionTitle, currentStatus}' \
  "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/agents/usage/hermes.json"
```

The plugin does not own that publisher. A missing or stale session must be corrected in the integration that writes the provider record.

## Nodes show offline

Run only the status surface used by the plugin:

```bash
command -v hermes-node
timeout 18s hermes-node status
```

The plugin does not modify node configuration, SSH keys, agents, host keys, or network routing. Diagnose those separately and do not add interactive SSH or remote execution to the panel.

## Status refresh failed

Check syntax and JSON output:

```bash
bash -n "$PLUGIN_DIR/scripts/hermes-status"
"$PLUGIN_DIR/scripts/hermes-status" | jq -e 'type == "object"'
```

Confirm required local tools:

```bash
command -v bash python3 jq systemctl
```

## Removal and recovery

Remove through Omarchy:

```bash
omarchy plugin remove "$PLUGIN_ID"
```

Removal deletes only the plugin checkout and its bar entry. It does not alter Hermes, the gateway, federation, or package-managed Omarchy files.
