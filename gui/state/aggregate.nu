# CLI version of the state aggregator (also implemented inline in
# gui/server/serve.nu). Used by `mise run gui:state:aggregate` for
# terminal inspection of joined state without launching the web server.

def aggregate_state [] {
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

aggregate_state | table
