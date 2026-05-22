# Provision a Hetzner host with cloud-init/kvm.yaml (passes --device=/dev/kvm
# to dockur). Will fail on Hetzner Cloud — only use against Dedicated Root /
# bare-metal-capable hosts.

^fnox exec --if-missing ignore -- hcloud server create --name $env.SERVER_NAME --type $env.SERVER_TYPE --image $env.SERVER_IMAGE --location $env.SERVER_LOCATION --ssh-key $env.SSH_KEY --user-data-from-file cloud-init/kvm.yaml

let probe = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | complete)
if $probe.exit_code == 0 {
    let ip = ($probe.stdout | str trim)
    if ($ip | is-not-empty) { ^ssh-keygen -R $ip out+err> /dev/null }
}

let provisioned_ip = (^fnox exec --if-missing ignore -- hcloud server ip $env.SERVER_NAME | str trim)
nu state/append.nu provisioned --label $env.SERVER_NAME --flavor kvm --sku $env.SERVER_TYPE --ip $provisioned_ip
