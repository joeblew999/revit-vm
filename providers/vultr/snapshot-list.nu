# List Vultr snapshots. Default: human table. --json: machine-readable.
#   nu providers/vultr/snapshot-list.nu
#   nu providers/vultr/snapshot-list.nu --json

def main [--json] {
    let listing = (^fnox exec --if-missing ignore -- vultr-cli snapshot list -o json | from json)
    let rows = ($listing.snapshots? | default [] | each {|s|
        {
            id: ($s.id | into string),
            description: ($s.description? | default ""),
            size_gb: ($s.size? | default 0),
            status: ($s.status? | default "unknown"),
            created: ($s.date_created? | default ""),
        }
    })
    if $json {
        $rows | to json -r
    } else {
        $rows | table -e
    }
}
