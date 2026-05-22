# Delete old Vultr snapshots that this repo created, keep the N newest.
# Filters by description prefix `vm-servers-` so we don't touch unrelated
# snapshots in the same Vultr account.

let keep = (($env.SNAPSHOTS_KEEP? | default "1") | into int)

let listing = (^fnox exec --if-missing ignore -- vultr-cli snapshot list -o json | from json)
let all_snaps = ($listing.snapshots? | default [])
let ours = ($all_snaps | where ($it.description? | default "" | str starts-with "vm-servers-") | sort-by date_created)
let total = ($ours | length)

print $"vm-servers- snapshots in Vultr: ($total), retention target: ($keep)"
if $total <= $keep {
    print "  nothing to do — under the retention limit"
    exit 0
}

let kept = ($ours | last $keep)
let purged = ($ours | first ($total - $keep))

print $"keeping newest ($keep):"
$kept | each {|s| print $"  ($s.id)  ($s.description)" } | ignore

print $"deleting older ($total - $keep):"
$purged | each {|s|
    print $"  delete ($s.id)  ($s.description)"
    ^fnox exec --if-missing ignore -- vultr-cli snapshot delete $s.id
} | ignore
