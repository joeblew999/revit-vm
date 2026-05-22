# Provision a new Hetzner VM from the latest snapshot. Errors clearly if
# no snapshot exists in the project.

let snaps = (^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | from json)
if ($snaps | is-empty) {
    print "No snapshots found — run `mise run snapshot:create` first (against a running VM)"
    exit 1
}

let snap = ($snaps | sort-by created | last)
print $"provisioning ($env.SERVER_NAME) from snapshot ($snap.id)"

^fnox exec --if-missing ignore -- hcloud server create --name $env.SERVER_NAME --type $env.SERVER_TYPE --image ($snap.id | into string) --location $env.SERVER_LOCATION --ssh-key $env.SSH_KEY

let probe = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | complete)
if $probe.exit_code == 0 {
    let ip = ($probe.stdout | str trim)
    if ($ip | is-not-empty) { ^ssh-keygen -R $ip out+err> /dev/null }
}

let provisioned_ip = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | str trim)
nu state/append.nu ({action: "provisioned-from-snapshot", label: $env.SERVER_NAME, ip: $provisioned_ip, snapshot_id: ($snap.id | into string)} | to json -r)
