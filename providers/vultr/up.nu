# Provision a Vultr Bare Metal instance with cloud-init/kvm.yaml. Async —
# returns once the create call accepts; the BM takes 5-10 min to rack
# and boot. Caller should run `rdp:wait` after to block until Windows is
# RDP-ready.

if ($env.VULTR_REGION | is-empty)     { print -e "VULTR_REGION not set in mise.local.toml";     exit 1 }
if ($env.VULTR_PLAN | is-empty)       { print -e "VULTR_PLAN not set in mise.local.toml";       exit 1 }
if ($env.VULTR_OS_ID | is-empty)      { print -e "VULTR_OS_ID not set in mise.local.toml";      exit 1 }
if ($env.VULTR_SSH_KEY_ID | is-empty) { print -e "VULTR_SSH_KEY_ID not set in mise.local.toml"; exit 1 }

print $"creating Vultr Bare Metal: label=($env.VULTR_LABEL) region=($env.VULTR_REGION) plan=($env.VULTR_PLAN) os=($env.VULTR_OS_ID)"

^fnox exec --if-missing ignore -- vultr-cli bare-metal create --region $env.VULTR_REGION --plan $env.VULTR_PLAN --os $env.VULTR_OS_ID --ssh $env.VULTR_SSH_KEY_ID --label $env.VULTR_LABEL --hostname $env.VULTR_LABEL --userdata-file cloud-init/kvm.yaml

print ""
print "Vultr BM provisioning started (async). Next:"
print "  mise run vm:status      # poll for active state"
print "  mise run rdp:wait       # block until Windows RDP is up"

# IP isn't assigned for a few minutes; record what we know now and let
# `vm:status` / `vm:ip` reflect the eventual IP.
nu state/append.nu provisioned --label $env.VULTR_LABEL --flavor kvm --sku $env.VULTR_PLAN --region $env.VULTR_REGION --plan $env.VULTR_PLAN
