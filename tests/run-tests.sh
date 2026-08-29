#!/usr/bin/env bash
# Fixture-driven regression tests for scripts/hermes-status.
#
# Every case runs the real adapter against a synthetic telemetry record in a
# throwaway HOME/XDG_STATE_HOME, with a PATH that contains only the
# interpreters the adapter needs. A real Hermes installation on the machine
# running these tests therefore cannot influence the result.

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
status_script="$repo_root/scripts/hermes-status"

sandbox="$(mktemp -d)"
trap 'rm -rf "$sandbox"' EXIT

base_bin="$sandbox/base-bin"
stub_bin="$sandbox/stub-bin"
probe_log="$sandbox/probes.log"
mkdir -p "$base_bin" "$stub_bin"

for tool in bash env jq python3 awk dirname; do
  tool_path="$(command -v "$tool" 2>/dev/null || true)"
  if [[ -z "$tool_path" ]]; then
    printf 'missing required tool: %s\n' "$tool" >&2
    exit 2
  fi
  ln -sf "$tool_path" "$base_bin/$tool"
done
bash_path="$(command -v bash)"

# Probes that record every invocation, so a test can prove remote mode never
# reaches out to the local host.
cat > "$stub_bin/hermes" <<EOS
#!/bin/sh
printf 'hermes\n' >> "$probe_log"
printf 'stub-hermes 9.9.9\n'
EOS
cat > "$stub_bin/hermes-node" <<EOS
#!/bin/sh
printf 'hermes-node\n' >> "$probe_log"
printf 'alpha: online\nbeta: offline\n'
EOS
cat > "$stub_bin/systemctl" <<EOS
#!/bin/sh
printf 'systemctl\n' >> "$probe_log"
exit 0
EOS
chmod +x "$stub_bin/hermes" "$stub_bin/hermes-node" "$stub_bin/systemctl"

tests_run=0
tests_failed=0
last_exit=0
epoch() { printf '%(%s)T' -1; }

# run_status <record|--no-record> [--with-local-hermes]
run_status() {
  local record="$1" mode="${2:-}"
  local home="$sandbox/home" state="$sandbox/state" path="$base_bin"
  rm -rf "$home" "$state"
  mkdir -p "$home" "$state/omarchy/agents/usage"
  if [[ "$record" != "--no-record" ]]; then
    printf '%s' "$record" > "$state/omarchy/agents/usage/hermes.json"
  fi
  if [[ "$mode" == "--with-local-hermes" ]]; then
    path="$stub_bin:$base_bin"
  fi
  : > "$probe_log"
  env -i HOME="$home" XDG_STATE_HOME="$state" PATH="$path" "$bash_path" "$status_script"
  last_exit=$?
}

check() {
  local name="$1" expected="$2" actual="$3"
  tests_run=$((tests_run + 1))
  if [[ "$expected" == "$actual" ]]; then
    printf 'ok   %s\n' "$name"
  else
    tests_failed=$((tests_failed + 1))
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$name" "$expected" "$actual"
  fi
}

field() {
  jq -r "$2" <<<"$1" 2>/dev/null || printf '<not-json>'
}

# --- no record, absent flag, explicit false --------------------------------

out="$(run_status --no-record)"
check "no record: exits 0" 0 "$last_exit"
check "no record: emits one JSON object" true "$(field "$out" 'type == "object"')"
check "no record: not remote" false "$(field "$out" '.remote')"
check "no record: not stale" false "$(field "$out" '.remoteStale')"
check "no record: not installed" false "$(field "$out" '.installed')"
check "no record: gateway unknown" unknown "$(field "$out" '.gatewayState')"
check "no record: no nodes" 0 "$(field "$out" '.nodesTotal')"

out="$(run_status '{"installed": true, "gatewayState": "active", "version": "record 1.0"}')"
check "no remote flag: record cannot claim install" false "$(field "$out" '.installed')"
check "no remote flag: record cannot claim gateway" unknown "$(field "$out" '.gatewayState')"
check "no remote flag: remote stays false" false "$(field "$out" '.remote')"

out="$(run_status '{"remote": false, "installed": true, "gatewayState": "active"}')"
check "remote false: local mode" false "$(field "$out" '.remote')"
check "remote false: record install ignored" false "$(field "$out" '.installed')"

out="$(run_status '{}')"
check "empty record: exits 0" 0 "$last_exit"
check "empty record: local mode" false "$(field "$out" '.remote')"

out="$(run_status '[1, 2, 3]')"
check "non-object record: exits 0" 0 "$last_exit"
check "non-object record: local mode" false "$(field "$out" '.remote')"

out="$(run_status 'not json at all')"
check "unparseable record: exits 0" 0 "$last_exit"
check "unparseable record: local mode" false "$(field "$out" '.remote')"

# --- strict boolean for remote mode ----------------------------------------

out="$(run_status "{\"remote\": true, \"installed\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(epoch)}")"
check "remote true: accepted" true "$(field "$out" '.remote')"
check "remote true: record install honoured" true "$(field "$out" '.installed')"

for bad in '"true"' '1' '"yes"' 'null' '[]' '{}'; do
  out="$(run_status "{\"remote\": $bad, \"installed\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(epoch)}")"
  check "remote $bad: rejected" false "$(field "$out" '.remote')"
  check "remote $bad: local probes still authoritative" false "$(field "$out" '.installed')"
done

# --- freshness policy ------------------------------------------------------

fresh_record="{\"remote\": true, \"installed\": true, \"gatewayState\": \"active\", \"activeModel\": \"m\", \"collectedAtEpoch\": $(epoch), \"staleAfterSec\": 300}"
out="$(run_status "$fresh_record")"
check "fresh record: not stale" false "$(field "$out" '.remoteStale')"
check "fresh record: gateway honoured" active "$(field "$out" '.gatewayState')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 3600 )), \"staleAfterSec\": 300}")"
check "stale record: marked stale" true "$(field "$out" '.remoteStale')"
check "stale record: gateway state stale" stale "$(field "$out" '.gatewayState')"

out="$(run_status '{"remote": true, "gatewayState": "active"}')"
check "missing timestamp: stale" true "$(field "$out" '.remoteStale')"
check "missing timestamp: gateway state stale" stale "$(field "$out" '.gatewayState')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) + 86400 )), \"staleAfterSec\": 300}")"
check "24h future timestamp: stale" true "$(field "$out" '.remoteStale')"
check "24h future timestamp: gateway state stale" stale "$(field "$out" '.gatewayState')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) + 60 )), \"staleAfterSec\": 300}")"
check "60s clock skew: tolerated" false "$(field "$out" '.remoteStale')"
check "60s clock skew: gateway honoured" active "$(field "$out" '.gatewayState')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 31536000 )), \"staleAfterSec\": 1000000000000000}")"
check "year-old record with huge TTL: stale" true "$(field "$out" '.remoteStale')"
check "year-old record with huge TTL: gateway state stale" stale "$(field "$out" '.gatewayState')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 1800 )), \"staleAfterSec\": 1000000000000000}")"
check "30m old record with huge TTL: clamped to policy and stale" true "$(field "$out" '.remoteStale')"
check "huge TTL clamped to policy maximum" 900 "$(field "$out" '.staleAfterSec')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 300 )), \"staleAfterSec\": 300}")"
check "age equal to TTL: expired at the boundary" true "$(field "$out" '.remoteStale')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 280 )), \"staleAfterSec\": 300}")"
check "age below TTL: still fresh" false "$(field "$out" '.remoteStale')"

for bad in '"600"' 'null' '[]' '"abc"'; do
  out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(( $(epoch) - 400 )), \"staleAfterSec\": $bad}")"
  check "staleAfterSec $bad: falls back to local default" true "$(field "$out" '.remoteStale')"
  check "staleAfterSec $bad: exits 0" 0 "$last_exit"
done

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(epoch), \"staleAfterSec\": -5}")"
check "negative staleAfterSec: exits 0" 0 "$last_exit"
check "negative staleAfterSec: clamped to a positive minimum" 1 "$(field "$out" '.staleAfterSec')"

out="$(run_status '{"remote": true, "gatewayState": "active", "collectedAtEpoch": -100, "staleAfterSec": 300}')"
check "negative timestamp: stale" true "$(field "$out" '.remoteStale')"

out="$(run_status '{"remote": true, "gatewayState": "active", "collectedAtEpoch": "1000", "staleAfterSec": 300}')"
check "string timestamp: stale" true "$(field "$out" '.remoteStale')"
check "string timestamp: exits 0" 0 "$last_exit"

out="$(run_status '{"remote": true, "gatewayState": "active", "collectedAtEpoch": 1e400, "staleAfterSec": 1e400}')"
check "infinite numbers: exits 0" 0 "$last_exit"
check "infinite numbers: stale" true "$(field "$out" '.remoteStale')"

out="$(run_status "{\"remote\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": 99999999999999999999, \"staleAfterSec\": 300}")"
check "absurd future timestamp: exits 0" 0 "$last_exit"
check "absurd future timestamp: stale" true "$(field "$out" '.remoteStale')"

# --- invalid gateway and installed values ----------------------------------

for bad in '"definitely-up"' '"ACTIVE"' '"active "' '123' '{"x": 1}' '["active"]' 'true'; do
  out="$(run_status "{\"remote\": true, \"gatewayState\": $bad, \"collectedAtEpoch\": $(epoch)}")"
  check "gatewayState $bad: fails closed to unknown" unknown "$(field "$out" '.gatewayState')"
done

for good in active stopped not-installed unknown; do
  out="$(run_status "{\"remote\": true, \"gatewayState\": \"$good\", \"collectedAtEpoch\": $(epoch)}")"
  check "gatewayState $good: accepted" "$good" "$(field "$out" '.gatewayState')"
done

for bad in '"true"' '1' '"yes"' '[]' '{}' 'null'; do
  out="$(run_status "{\"remote\": true, \"installed\": $bad, \"collectedAtEpoch\": $(epoch)}")"
  check "installed $bad: rejected" false "$(field "$out" '.installed')"
done

for bad in '"true"' '1' '"yes"'; do
  out="$(run_status "{\"remote\": true, \"hermesNodeAvailable\": $bad, \"collectedAtEpoch\": $(epoch)}")"
  check "hermesNodeAvailable $bad: rejected" false "$(field "$out" '.hermesNodeAvailable')"
done

out="$(run_status "{\"remote\": true, \"hermesNodeAvailable\": true, \"collectedAtEpoch\": $(epoch)}")"
check "hermesNodeAvailable true: accepted" true "$(field "$out" '.hermesNodeAvailable')"

# --- capped strings and preserved extra fields -----------------------------

long_version="$(printf 'v%.0s' $(seq 1 5000))"
long_model="$(printf 'm%.0s' $(seq 1 5000))"
out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"version\": \"$long_version\", \"activeModel\": \"$long_model\", \"currentSessionId\": 12345, \"tokensUsed\": 42}")"
check "version capped at 512" 512 "$(field "$out" '.version | length')"
check "activeModel capped at 256" 256 "$(field "$out" '.activeModel | length')"
check "session id coerced to string" '"12345"' "$(field "$out" '.currentSessionId | tojson')"
check "unknown record fields preserved" 42 "$(field "$out" '.tokensUsed')"

# --- local probe suppression ------------------------------------------------

out="$(run_status "{\"remote\": true, \"installed\": true, \"gatewayState\": \"active\", \"collectedAtEpoch\": $(epoch)}" --with-local-hermes)"
check "remote mode: no local probe ran" "" "$(cat "$probe_log")"
check "remote mode: install from record" true "$(field "$out" '.installed')"
check "remote mode: gateway from record" active "$(field "$out" '.gatewayState')"
check "remote mode: version from record, not local hermes" "" "$(field "$out" '.version')"

out="$(run_status '{"remote": "true", "installed": true, "gatewayState": "active"}' --with-local-hermes)"
check "string remote: local probes still run" true "$(grep -qx hermes "$probe_log" && echo true || echo false)"
check "string remote: version from local hermes" "stub-hermes 9.9.9" "$(field "$out" '.version')"

out="$(run_status --no-record --with-local-hermes)"
check "local mode: probes ran" true "$(test -s "$probe_log" && echo true || echo false)"
check "local mode: installed from probe" true "$(field "$out" '.installed')"
check "local mode: gateway from systemctl" active "$(field "$out" '.gatewayState')"
check "local mode: nodes from hermes-node" 2 "$(field "$out" '.nodesTotal')"
check "local mode: online nodes counted" 1 "$(field "$out" '.nodesOnline')"

# --- malformed node maps and counters --------------------------------------

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": \"aaaaaaaaaa\"}")"
check "string nodes: exits 0" 0 "$last_exit"
check "string nodes: replaced by empty map" '{}' "$(field "$out" '.nodes | tojson')"
check "string nodes: character count is not a node count" 0 "$(field "$out" '.nodesTotal')"

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": [\"a\", \"b\"]}")"
check "array nodes: replaced by empty map" '{}' "$(field "$out" '.nodes | tojson')"
check "array nodes: no node count" 0 "$(field "$out" '.nodesTotal')"

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodesTotal\": \"12\", \"nodesOnline\": \"7\"}")"
check "string counters: exits 0" 0 "$last_exit"
check "string counters: emits JSON" true "$(field "$out" 'type == "object"')"
check "string nodesTotal: falls back to derived count" 0 "$(field "$out" '.nodesTotal')"
check "string nodesOnline: falls back to derived count" 0 "$(field "$out" '.nodesOnline')"

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodesTotal\": -4, \"nodesOnline\": -9}")"
check "negative counters: clamped to zero" 0 "$(field "$out" '.nodesTotal')"
check "negative online counter: clamped to zero" 0 "$(field "$out" '.nodesOnline')"

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodesTotal\": 1e18, \"nodesOnline\": 1e18}")"
check "huge counters: bounded" 65536 "$(field "$out" '.nodesTotal')"
check "huge online counter: bounded by total" 65536 "$(field "$out" '.nodesOnline')"

out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": {\"alpha\": {\"online\": true}}, \"nodesTotal\": 3, \"nodesOnline\": 9}")"
check "online counter cannot exceed total" 3 "$(field "$out" '.nodesOnline')"

bad_nodes='{"good": {"online": true},'
bad_nodes+=' "bad key!": {"online": true},'
bad_nodes+=' "../../etc/passwd": {"online": true},'
bad_nodes+=' "stringy": "online",'
bad_nodes+=' "listy": [1, 2],'
bad_nodes+=' "coerced": {"online": "true"}}'
out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": $bad_nodes}")"
check "malformed node map: only valid aliases kept" '["coerced","good"]' "$(field "$out" '.nodes | keys | tojson')"
check "malformed node map: derived total" 2 "$(field "$out" '.nodesTotal')"
check "malformed node map: string online is not true" false "$(field "$out" '.nodes.coerced.online')"
check "malformed node map: boolean online preserved" true "$(field "$out" '.nodes.good.online')"
check "malformed node map: derived online count" 1 "$(field "$out" '.nodesOnline')"

long_alias="$(printf 'a%.0s' $(seq 1 65))"
out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": {\"$long_alias\": {\"online\": true}}}")"
check "over-long node alias: dropped" '{}' "$(field "$out" '.nodes | tojson')"

many_nodes="$(jq -cn '[range(0; 400) | {key: ("n" + (. | tostring)), value: {online: true}}] | from_entries')"
out="$(run_status "{\"remote\": true, \"collectedAtEpoch\": $(epoch), \"nodes\": $many_nodes}")"
check "oversized node map: capped" 256 "$(field "$out" '.nodes | length')"

# --- summary ----------------------------------------------------------------

printf '\n%d test(s), %d failure(s)\n' "$tests_run" "$tests_failed"
[[ "$tests_failed" -eq 0 ]]
