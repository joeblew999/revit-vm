# Provider dispatcher. Every `vm:*` / `snapshot:*` mise task is a one-liner
# that calls this with the action name; we route to the matching script
# under providers/{hetzner,vultr}/.
#
# Mapping is convention-based: action "snapshot-create" → providers/<provider>/snapshot-create.nu.
#
# --label and --provider override env at the dispatcher level so a single
# call site can target any VM:
#
#   nu lifecycle/dispatch.nu up
#   nu lifecycle/dispatch.nu snapshot-create
#   nu lifecycle/dispatch.nu down --label vm-b               # specific label
#   nu lifecycle/dispatch.nu status --label vm-b --provider vultr
#
# Or via mise (args after `--` flow through):
#   mise run vm:down -- --label vm-b
#   mise run snapshot:create -- --label vm-b
#
# Overrides mutate $env in this script, which the spawned provider script
# inherits — bypasses mise's [env] re-injection because we're already past
# mise.toml's [env] resolution.

def main [
    action: string
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

    let cur_provider = ($env.VM_PROVIDER? | default "")
    if $cur_provider not-in ["hetzner", "vultr"] {
        print -e $"VM_PROVIDER must be 'hetzner' or 'vultr' \(got '($cur_provider)'\)"
        exit 1
    }

    if ($label | is-not-empty) {
        match $cur_provider {
            "hetzner" => { $env.SERVER_NAME = $label }
            "vultr"   => { $env.VULTR_LABEL = $label }
        }
    }

    let script = $"providers/($cur_provider)/($action).nu"
    if not ($script | path exists) {
        print -e $"no such action for provider ($cur_provider): ($script) not found"
        exit 1
    }

    ^nu $script
    exit $env.LAST_EXIT_CODE
}
