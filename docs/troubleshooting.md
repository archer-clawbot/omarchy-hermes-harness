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
