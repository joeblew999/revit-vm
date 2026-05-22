# Typed writers for VM lifecycle events in state/vms.jsonl.
#
# JSONL has no header concept — each line stands alone. The contract for
# what fields go where lives in state/vms.schema.json and is *enforced* here
# by nushell's typed flags on each `main <event>` subcommand. Missing or
# wrong-typed fields fail at parse time, not silently in production.
#
# Callers invoke as a subprocess (matches the rest of the repo's pattern):
#
#   nu state/append.nu provisioned --label foo --flavor qemu --ip 1.2.3.4
#   nu state/append.nu provisioned-from-snapshot --label foo --snapshot-id 99 --ip 1.2.3.4
#   nu state/append.nu snapshotted --label foo --description foo-20260522 --snapshot-id 12345
#   nu state/append.nu destroyed --label foo
#
# Auto-filled fields: ts (ISO 8601 with offset), provider ($VM_PROVIDER).
# Persistence is git: `git add state/vms.jsonl && git push` after lifecycle ops.

def now_ts [] {
    date now | format date "%Y-%m-%dT%H:%M:%S%z"
}

def write_event [event: record] {
    let enriched = ($event
        | upsert ts (now_ts)
        | upsert provider $env.VM_PROVIDER)
    # JSONL requires a newline between records — `save -a` does not add one.
    let line = ($enriched | to json -r)
    $"($line)\n" | save -a state/vms.jsonl
    # Publish to xs when the store is running — powers the GUI SSE stream and
    # lets MCP clients tail live lifecycle events without polling the JSONL file.
    # Degrade silently if xs isn't reachable — the jsonl write above is the
    # source of truth; xs is the live-broadcast convenience layer.
    if ($env.XS_ADDR? | is-not-empty) {
        let r = ($line | ^xs append $env.XS_ADDR vm.lifecycle | complete)
        if $r.exit_code != 0 {
            print -e $"\(xs unreachable at ($env.XS_ADDR) — event appended to jsonl only\)"
        }
    }
}

def "main provisioned" [
    --label: string,                 # VM identity (SERVER_NAME / VULTR_LABEL)
    --flavor: string,                # "qemu" | "kvm"
    --sku: string = "",              # provider-side SKU (Hetzner SERVER_TYPE e.g. cpx42; Vultr plan e.g. vbm-4c-32gb). Used for cost attribution.
    --ip: string = "",               # public IPv4 if known (Vultr is async, may be empty)
    --region: string = "",           # Vultr only
    --plan: string = "",             # Vultr only (legacy — superseded by --sku)
] {
    if ($label | is-empty)  { print -e "--label required";  exit 2 }
    if ($flavor | is-empty) { print -e "--flavor required"; exit 2 }
    if $flavor not-in ["qemu", "kvm"] { print -e $"--flavor must be qemu|kvm \(got ($flavor)\)"; exit 2 }

    mut e = {action: "provisioned", label: $label, flavor: $flavor}
    if ($sku | is-not-empty)    { $e = ($e | upsert sku $sku) }
    if ($ip | is-not-empty)     { $e = ($e | upsert ip $ip) }
    if ($region | is-not-empty) { $e = ($e | upsert region $region) }
    if ($plan | is-not-empty)   { $e = ($e | upsert plan $plan) }
    write_event $e
}

def "main provisioned-from-snapshot" [
    --label: string,
    --snapshot-id: string,
    --ip: string = "",
] {
    if ($label | is-empty)       { print -e "--label required";       exit 2 }
    if ($snapshot_id | is-empty) { print -e "--snapshot-id required"; exit 2 }

    mut e = {action: "provisioned-from-snapshot", label: $label, snapshot_id: $snapshot_id}
    if ($ip | is-not-empty) { $e = ($e | upsert ip $ip) }
    write_event $e
}

def "main snapshotted" [
    --label: string,
    --description: string,
    --snapshot-id: string = "",      # Hetzner doesn't always capture; Vultr always does
] {
    if ($label | is-empty)       { print -e "--label required";       exit 2 }
    if ($description | is-empty) { print -e "--description required"; exit 2 }

    mut e = {action: "snapshotted", label: $label, description: $description}
    if ($snapshot_id | is-not-empty) { $e = ($e | upsert snapshot_id $snapshot_id) }
    write_event $e
}

def "main destroyed" [
    --label: string,
    --bm-id: string = "",            # Vultr only
] {
    if ($label | is-empty) { print -e "--label required"; exit 2 }

    mut e = {action: "destroyed", label: $label}
    if ($bm_id | is-not-empty) { $e = ($e | upsert bm_id $bm_id) }
    write_event $e
}

def main [] {
    print "Usage: nu state/append.nu <event> [flags]"
    print ""
    print "Events:"
    print "  provisioned                 fresh VM created"
    print "  provisioned-from-snapshot   VM restored from snapshot"
    print "  snapshotted                 snapshot taken"
    print "  destroyed                   VM deleted"
    print ""
    print "Contract: state/vms.schema.json"
    exit 2
}
