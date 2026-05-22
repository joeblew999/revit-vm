# Pull the sibling vm-software repo so installs.jsonl is current.
# vm-servers's own state/vms.jsonl is local — written by the lifecycle
# scripts in this repo, no pull needed. Idempotent; safe to put on a
# loop at $REFRESH_INTERVAL_SEC.

if ($env.VM_SOFTWARE_REPO | is-empty) {
    print -e "VM_SOFTWARE_REPO not set in mise.local.toml — skipping vm-software pull"
    exit 0
}
if not ($env.VM_SOFTWARE_REPO | path exists) {
    print -e $"vm-software path '($env.VM_SOFTWARE_REPO)' doesn't exist — skipping"
    exit 0
}

print $"  pulling ($env.VM_SOFTWARE_REPO)"
cd $env.VM_SOFTWARE_REPO
let out = (^git pull --ff-only | complete)
if $out.exit_code != 0 {
    print -e $"  pull failed: ($out.stderr | str trim)"
} else {
    print ($out.stdout | str trim | str replace -a "\n" "\n    ")
}
