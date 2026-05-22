# Top-level `start` orchestrator: provisions (from snapshot if any, else
# fresh), waits for RDP, opens it. Provider-aware via lifecycle/dispatch.nu.

def must [label: string, cmd: closure] {
    do $cmd
    if $env.LAST_EXIT_CODE != 0 {
        print -e $"($label) failed \(rc=($env.LAST_EXIT_CODE)\) — aborting"
        exit $env.LAST_EXIT_CODE
    }
}

let has_snapshot = match $env.VM_PROVIDER {
    "hetzner" => {
        let r = (^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | complete)
        if $r.exit_code != 0 { false } else { (($r.stdout | from json) | length) > 0 }
    },
    "vultr" => {
        let r = (^fnox exec --if-missing ignore -- vultr-cli snapshot list -o json | complete)
        if $r.exit_code != 0 {
            false
        } else {
            let snaps = (($r.stdout | from json).snapshots? | default [])
            ($snaps | where ($it.description? | default "" | str starts-with "vm-servers-") | length) > 0
        }
    },
    _ => {
        print -e $"VM_PROVIDER must be 'hetzner' or 'vultr' \(got '($env.VM_PROVIDER)'\)"
        exit 1
        false
    }
}

if $has_snapshot {
    print "→ booting from latest snapshot"
    must "vm:up-snap" { ^nu lifecycle/dispatch.nu up-snap }
} else {
    print "→ no snapshot — fresh provision (~1hr on Hetzner TCG, ~6 min on Vultr KVM)"
    must "vm:up" { ^nu lifecycle/dispatch.nu up }
}

must "rdp:wait"    { ^nu connect/rdp-wait.nu }
must "rdp:install" { ^nu connect/rdp-install.nu }
must "rdp:open"    { ^nu connect/rdp-open.nu }
