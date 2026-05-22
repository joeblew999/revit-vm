# Delete old Hetzner snapshots, keep the N newest. Read SNAPSHOTS_KEEP from
# env (default 1). Safe to run any time — never deletes more than (total-N)
# and never the newest.

let keep = (($env.SNAPSHOTS_KEEP? | default "1") | into int)
let snaps = (^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | from json | sort-by created)
let total = ($snaps | length)
print $"snapshots in project: ($total), retention target: ($keep)"

if $total <= $keep {
    print "  nothing to do — under the retention limit"
    exit 0
}

let kept = ($snaps | last $keep)
let purged = ($snaps | first ($total - $keep))

print $"keeping newest ($keep):"
$kept | each {|s| print $"  ($s.id)  ($s.description)" } | ignore

print $"deleting older ($total - $keep):"
$purged | each {|s|
    print $"  delete ($s.id)"
    ^fnox exec --if-missing ignore -- hcloud image delete ($s.id | into string)
} | ignore
