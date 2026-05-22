# List operating systems available for fresh BM installs. Default in
# mise.toml is 1743 (Ubuntu 24.04 x64) — the host OS that runs dockur.
# You almost never need to change this; check here only if Vultr retires
# an Ubuntu LTS and the existing ID stops working.

let raw = (^fnox exec --if-missing ignore -- vultr-cli os list -o json | from json)
let oss = ($raw.os? | default $raw)

if ($oss | describe) =~ "list" {
    print "Ubuntu OSes (most likely candidates):"
    $oss | where ($it.name? | default "" | str contains -i "ubuntu") | each {|o|
        let id = ($o.id? | default "?")
        let name = ($o.name? | default "?")
        let arch = ($o.arch? | default "?")
        print $"  ($id)  ($name) [($arch)]"
    } | ignore
} else {
    print "(could not parse OS JSON — falling back to raw)"
    ^fnox exec --if-missing ignore -- vultr-cli os list
}
