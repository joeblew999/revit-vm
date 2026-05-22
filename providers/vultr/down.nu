# Delete the Vultr BM matching $env.VULTR_LABEL. No-op (exit 0) if no
# match — same shape as Hetzner `vm:down` on a missing server.

let listing = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | from json)
let matches = ($listing.bare_metals? | default [] | where label == $env.VULTR_LABEL)
if ($matches | is-empty) {
    print $"no Vultr Bare Metal with label '($env.VULTR_LABEL)' — nothing to delete"
    exit 0
}
let id = ($matches | first | get id)
print $"deleting Vultr BM ($id) ($env.VULTR_LABEL)"
^fnox exec --if-missing ignore -- vultr-cli bare-metal delete $id
nu state/append.nu ({action: "destroyed", label: $env.VULTR_LABEL, bm_id: $id} | to json -r)
