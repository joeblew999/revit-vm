^fnox exec --if-missing ignore -- hcloud server delete $env.SERVER_NAME
nu state/append.nu ({action: "destroyed", label: $env.SERVER_NAME} | to json -r)
