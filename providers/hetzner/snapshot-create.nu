# Snapshot the Hetzner VM. Hot snapshot — for cleanest results, the caller
# (e.g. the `stop` task) shuts Windows down via `docker stop --timeout=120`
# before invoking this.

let ts = (date now | format date "%Y%m%d-%H%M%S")
let desc = $"($env.SERVER_NAME)-($ts)"
print $"creating snapshot: ($desc)"
^fnox exec --if-missing ignore -- hcloud server create-image --type snapshot --description $desc $env.SERVER_NAME

# Look up the snapshot we just created by description, so we can record its
# ID. Tolerates lookup failure — schema makes snapshot_id optional here.
let lookup = (^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | complete)
let snap_id = (if $lookup.exit_code == 0 {
    let matches = ($lookup.stdout | from json | where description == $desc)
    if ($matches | is-empty) { "" } else { $matches | first | get id | into string }
} else { "" })

if ($snap_id | is-empty) {
    nu state/append.nu snapshotted --label $env.SERVER_NAME --description $desc
} else {
    nu state/append.nu snapshotted --label $env.SERVER_NAME --description $desc --snapshot-id $snap_id
}
