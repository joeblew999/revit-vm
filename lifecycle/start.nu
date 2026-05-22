# Top-level `start` orchestrator: provisions (from snapshot if any, else
# fresh), waits for RDP, opens it. Provider-aware via lifecycle/dispatch.nu.
#
# Usage:
#   nu lifecycle/start.nu                                       # uses mise.toml defaults
#   nu lifecycle/start.nu --label vm-foo                        # override SERVER_NAME / VULTR_LABEL
#   nu lifecycle/start.nu --label vm-foo --provider hetzner     # also pick provider per-call
#
# Args are CLI flags so they bypass mise's [env] re-injection. Inside this
# script we mutate $env.SERVER_NAME / $env.VULTR_LABEL / $env.VM_PROVIDER
# so the downstream dispatcher + provider scripts pick them up.

def must [label: string, cmd: closure] {
    do $cmd
    if $env.LAST_EXIT_CODE != 0 {
        print -e $"($label) failed \(rc=($env.LAST_EXIT_CODE)\) — aborting"
        exit $env.LAST_EXIT_CODE
    }
}

def main [
    --label: string = ""        # VM identity; overrides SERVER_NAME (hetzner) or VULTR_LABEL (vultr)
    --provider: string = ""     # "hetzner" | "vultr"; overrides $env.VM_PROVIDER
] {
    if ($provider | is-not-empty) {
        if $provider not-in ["hetzner", "vultr"] {
            print -e $"--provider must be hetzner|vultr \(got '($provider)'\)"
            exit 2
        }
        $env.VM_PROVIDER = $provider
    }
    if ($label | is-not-empty) {
        match $env.VM_PROVIDER {
            "hetzner" => { $env.SERVER_NAME = $label }
            "vultr"   => { $env.VULTR_LABEL = $label }
            _ => { print -e $"unknown provider for label override: ($env.VM_PROVIDER)"; exit 1 }
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
        print $"→ booting from latest snapshot for label=($env.SERVER_NAME? | default $env.VULTR_LABEL?)"
        must "vm:snap-up" { ^nu lifecycle/dispatch.nu snap-up }
    } else {
        print $"→ no snapshot — fresh provision for label=($env.SERVER_NAME? | default $env.VULTR_LABEL?)"
        must "vm:up" { ^nu lifecycle/dispatch.nu up }
    }

    must "rdp:wait"    { ^nu connect/rdp-wait.nu }
    must "rdp:install" { ^nu connect/rdp-install.nu }
    must "rdp:open"    { ^nu connect/rdp-open.nu }
}
