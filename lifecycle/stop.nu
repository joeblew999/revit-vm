# Top-level `stop` orchestrator: clean-shut Windows → snapshot → prune
# older → destroy. Aborts on first failure so state is never destroyed
# without first being saved.

def must [label: string, cmd: closure] {
    do $cmd
    if $env.LAST_EXIT_CODE != 0 {
        print -e $"($label) failed \(rc=($env.LAST_EXIT_CODE)\) — aborting before continuing"
        exit $env.LAST_EXIT_CODE
    }
}

let ip = (^nu lifecycle/dispatch.nu ip | str trim)
let key = ($env.SSH_KEY_FILE | str replace --regex '^~' $env.HOME)

print "→ clean-shutting Windows (ACPI via docker stop, up to 120s)"
must "docker stop" {
    ^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" "docker stop --timeout=120 windows"
}

must "snapshot:create" { ^nu lifecycle/dispatch.nu snapshot-create }
must "snapshot:prune"  { ^nu lifecycle/dispatch.nu snapshot-prune }
must "vm:down"         { ^nu lifecycle/dispatch.nu down }
