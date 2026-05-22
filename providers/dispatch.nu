# Provider dispatcher. Every `vm:*` / `snapshot:*` mise task is a one-liner
# that calls this with the action name; we route to the matching script
# under providers/{hetzner,vultr}/.
#
# Mapping is convention-based: action "snapshot-create" → providers/<provider>/snapshot-create.nu.
#
# Usage:
#   nu providers/dispatch.nu up
#   nu providers/dispatch.nu snapshot-create

def main [action: string] {
    let provider = ($env.VM_PROVIDER? | default "")
    if $provider not-in ["hetzner", "vultr"] {
        print -e $"VM_PROVIDER must be 'hetzner' or 'vultr' \(got '($provider)'\)"
        exit 1
    }

    let script = $"providers/($provider)/($action).nu"
    if not ($script | path exists) {
        print -e $"no such action for provider ($provider): ($script) not found"
        exit 1
    }

    ^nu $script
    exit $env.LAST_EXIT_CODE
}
