# Top-level `stop` orchestrator: clean-shut Windows → snapshot → prune
# older → destroy. Aborts on first failure so state is never destroyed
# without first being saved.
#
# Usage:
#   nu lifecycle/stop.nu                                      # uses mise.toml defaults
#   nu lifecycle/stop.nu --label vm-foo                       # stop a specific labeled VM
#   nu lifecycle/stop.nu --label vm-foo --provider hetzner    # also pick provider

def must [label: string, cmd: closure] {
    do $cmd
    if $env.LAST_EXIT_CODE != 0 {
        print -e $"($label) failed \(rc=($env.LAST_EXIT_CODE)\) — aborting before continuing"
        exit $env.LAST_EXIT_CODE
    }
}

def main [
    --label: string = ""
    --provider: string = ""
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

    let ip = (^nu lifecycle/dispatch.nu ip | str trim)
    let key = ($env.SSH_KEY_FILE | str replace --regex '^~' $env.HOME)

    print "→ clean-shutting Windows (ACPI via docker stop, up to 120s)"
    # Find whatever dockur container is actually running and stop it. Tolerates
    # the container being named anything (e.g. snapshots taken before the
    # 2026-05-22 rename used `windows_batch_processor`). If no container is
    # running, this is a no-op — the snapshot/destroy phase can still proceed.
    must "docker stop" {
        let cmd = '
NAME=$(docker ps --format "{{.Names}}" --filter "ancestor=dockurr/windows" | head -1)
if [ -z "$NAME" ]; then
  # Fallback: any running container with windows in the name
  NAME=$(docker ps --format "{{.Names}}" | grep -i windows | head -1)
fi
if [ -z "$NAME" ]; then
  echo "(no dockur container running — skipping docker stop)"
  exit 0
fi
echo "stopping container: $NAME"
docker stop --timeout=120 "$NAME"
'
        ^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" $cmd
    }

    must "snapshot:create" { ^nu lifecycle/dispatch.nu snapshot-create }
    must "snapshot:prune"  { ^nu lifecycle/dispatch.nu snapshot-prune }
    must "vm:down"         { ^nu lifecycle/dispatch.nu down }
}
