# Provision a Hetzner Cloud VM with cloud-init-qemu.yaml (TCG, KVM=N).
# Required env: SERVER_NAME, SERVER_TYPE, SERVER_IMAGE, SERVER_LOCATION, SSH_KEY

^fnox exec --if-missing ignore -- hcloud server create --name $env.SERVER_NAME --type $env.SERVER_TYPE --image $env.SERVER_IMAGE --location $env.SERVER_LOCATION --ssh-key $env.SSH_KEY --user-data-from-file cloud-init-qemu.yaml

# Clear any stale SSH host key for the recycled IPv4.
let probe = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | complete)
if $probe.exit_code == 0 {
    let ip = ($probe.stdout | str trim)
    if ($ip | is-not-empty) { ^ssh-keygen -R $ip out+err> /dev/null }
}

# Record the provisioning event.
let provisioned_ip = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | str trim)
nu state/append.nu provisioned --label $env.SERVER_NAME --flavor qemu --ip $provisioned_ip
