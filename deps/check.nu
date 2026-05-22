# Verify the active provider's API token is seeded in macOS keychain and
# any provider-specific config is in place. CLI presence is mise's job —
# `mise install` guarantees hcloud, vultr-cli, aws, fnox, nushell, etc.

match $env.VM_PROVIDER {
    "hetzner" => {
        let probe = (^fnox get HCLOUD_TOKEN | complete)
        if $probe.exit_code != 0 {
            print -e "HCLOUD_TOKEN missing in keychain — run: mise run token:set"
            exit 1
        }
        let ver = (^hcloud version | lines | first | str replace -r '^hcloud\s+' '' | str trim)
        print $"ok \(hetzner\): hcloud ($ver), HCLOUD_TOKEN present"
    }
    "vultr" => {
        let probe = (^fnox get VULTR_API_KEY | complete)
        if $probe.exit_code != 0 {
            print -e "VULTR_API_KEY missing in keychain — run: mise run vultr:token:set"
            exit 1
        }
        if ($env.VULTR_REGION | is-empty) or ($env.VULTR_PLAN | is-empty) or ($env.VULTR_SSH_KEY_ID | is-empty) {
            print -e "VULTR_REGION / VULTR_PLAN / VULTR_SSH_KEY_ID must be set in mise.local.toml"
            exit 1
        }
        let ver = (^vultr-cli version | lines | first | str trim)
        print $"ok \(vultr\): vultr-cli ($ver), VULTR_API_KEY present"
    }
    _ => {
        print -e $"VM_PROVIDER must be 'hetzner' or 'vultr' \(got: '($env.VM_PROVIDER)'\)"
        exit 1
    }
}
