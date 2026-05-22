^fnox exec --if-missing ignore -- hcloud server delete $env.SERVER_NAME
nu state/append.nu destroyed --label $env.SERVER_NAME
