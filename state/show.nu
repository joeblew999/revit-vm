# Show vm lifecycle events from state/vms.jsonl as a table.

let path = "state/vms.jsonl"
if not ($path | path exists) {
    print "(no events recorded yet — state/vms.jsonl doesn't exist)"
    exit 0
}

open $path | lines | where ($it | is-not-empty) | each {|l| $l | from json } | table
