# Shared aggregator for gui's read-only status board. Joins this repo's
# vms.jsonl with the sibling vm-software repo's installs.jsonl. Both
# the CLI view (gui/state/aggregate.nu) and the http-nu server
# (gui/server/serve.nu) import this — keeps the join logic in one place.

export def aggregate_state [] {
    let vms_path = "state/vms.jsonl"
    let installs_path = $"($env.VM_SOFTWARE_REPO)/state/installs.jsonl"

    let vms = (if ($vms_path | path exists) {
        open $vms_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    let installs = (if ($installs_path | path exists) {
        open $installs_path | lines | where ($it | is-not-empty) | each {|l| $l | from json }
    } else { [] })

    let latest_vms = ($vms | group-by label | values | each {|grp| $grp | sort-by ts | last })

    {
        vms: $latest_vms,
        installs_count: ($installs | length),
        installs_recent: ($installs | sort-by ts | last 10)
    }
}
