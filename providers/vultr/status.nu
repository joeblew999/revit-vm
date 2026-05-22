let listing = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | from json)
let matches = ($listing.bare_metals? | default [] | where label == $env.VULTR_LABEL)
if ($matches | is-empty) {
    print -e $"no Vultr Bare Metal with label '($env.VULTR_LABEL)'"
    exit 1
}
^fnox exec --if-missing ignore -- vultr-cli bare-metal get ($matches | first | get id)
