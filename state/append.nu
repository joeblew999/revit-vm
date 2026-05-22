# Append a single VM lifecycle event to state/vms.jsonl. Called from
# other scripts via `nu state/append.nu '{"action": "...", ...}'`.
#
# Each line is one JSON record. The `ts` and `provider` fields are filled
# in automatically — caller supplies the action-specific fields.
#
# `git push` after this is the persistence story (sibling vm-gui reads
# the latest state via `git pull`).

def main [event_json: string] {
    let event = ($event_json | from json)
    let enriched = ($event
        | upsert ts (date now | format date "%Y-%m-%dT%H:%M:%S%z")
        | upsert provider $env.VM_PROVIDER)
    $enriched | to json -r | save -a state/vms.jsonl
}
