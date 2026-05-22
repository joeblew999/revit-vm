# Snapshot the Hetzner VM. Hot snapshot — for cleanest results, the caller
# (e.g. the `stop` task) shuts Windows down via `docker stop --timeout=120`
# before invoking this.

let ts = (date now | format date "%Y%m%d-%H%M%S")
let desc = $"($env.SERVER_NAME)-($ts)"
print $"creating snapshot: ($desc)"
^fnox exec --if-missing ignore -- hcloud server create-image --type snapshot --description $desc $env.SERVER_NAME
nu state/append.nu ({action: "snapshotted", label: $env.SERVER_NAME, description: $desc} | to json -r)
