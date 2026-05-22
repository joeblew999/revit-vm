# List Hetzner snapshots. Default: human table. --json: machine-readable.
#   nu providers/hetzner/snapshot-list.nu
#   nu providers/hetzner/snapshot-list.nu --json

def main [--json] {
    let raw = (^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | from json)
    let rows = ($raw | each {|s|
        {
            id: ($s.id | into string),
            description: ($s.description? | default ""),
            image_size_gb: ($s.image_size? | default 0),
            created: ($s.created? | default ""),
        }
    })
    if $json {
        $rows | to json -r
    } else {
        $rows | table -e
    }
}
