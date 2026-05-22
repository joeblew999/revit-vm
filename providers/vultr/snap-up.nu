# Provision a Vultr Bare Metal from the latest vm-servers-* snapshot.
# Uses `bare-metal create --snapshot <id>` instead of --os, so the BM
# boots straight into the saved Windows state — no cloud-init re-run,
# no fresh install.

if ($env.VULTR_REGION | is-empty)     { print -e "VULTR_REGION not set in mise.local.toml";     exit 1 }
if ($env.VULTR_PLAN | is-empty)       { print -e "VULTR_PLAN not set in mise.local.toml";       exit 1 }
if ($env.VULTR_SSH_KEY_ID | is-empty) { print -e "VULTR_SSH_KEY_ID not set in mise.local.toml"; exit 1 }

let listing = (^fnox exec --if-missing ignore -- vultr-cli snapshot list -o json | from json)
let ours = ($listing.snapshots? | default [] | where ($it.description? | default "" | str starts-with "vm-servers-") | sort-by date_created)
if ($ours | is-empty) {
    print -e "No vm-servers-* snapshots found in Vultr. Run `mise run snapshot:create` first (requires R2 to be wired — see `mise run r2:bootstrap`)."
    exit 1
}
let snap = ($ours | last)
print $"provisioning ($env.VULTR_LABEL) from snapshot ($snap.id) — ($snap.description)"

^fnox exec --if-missing ignore -- vultr-cli bare-metal create --region $env.VULTR_REGION --plan $env.VULTR_PLAN --snapshot $snap.id --ssh $env.VULTR_SSH_KEY_ID --label $env.VULTR_LABEL --hostname $env.VULTR_LABEL

print ""
print "Vultr BM provisioning from snapshot started (async). Next:"
print "  mise run vm:status      # poll for active state"
print "  mise run rdp:wait       # block until Windows RDP is up"

nu state/append.nu provisioned-from-snapshot --label $env.VULTR_LABEL --snapshot-id $snap.id
